defmodule Mentor.Ecto.JSONSchema do
  @moduledoc """
  Helper module to generate JSON Schema based on Ecto schema.

  JSON Schema comes in many flavors and different LLMs have different limitations. Currently, this module aims to implement a schema suitable for [OpenAI structured outputs](https://platform.openai.com/docs/guides/structured-outputs/supported-schemas). This type of JSON schema may not be optimal or compatible with other models. Therefore, it's recommended to use this module as a starting point to generate a schema during development.

  > #### Warning {: .warning}
  >
  > For the reasons described above, neither backward compatibility nor compatibility with all built-in adapters are goals of this module.
  """

  defguardp is_ecto_schema(mod) when is_atom(mod)
  defguardp is_ecto_types(types) when is_map(types)

  @doc """
  Generates a JSON Schema from an Ecto schema.
  """
  def from_ecto_schema(ecto_schema) do
    defs =
      for schema <- bfs_from_ecto_schema([ecto_schema], %MapSet{}), into: %{} do
        {schema.title, schema}
      end

    title =
      if is_ecto_schema(ecto_schema) do
        title_for(ecto_schema)
      else
        "root"
      end

    title_ref = "#/$defs/#{title}"

    refs =
      find_all_values(defs, fn
        {_, ^title_ref} -> true
        _ -> false
      end)

    # Remove root from defs to save tokens if it's not referenced recursively
    {root, defs} =
      case refs do
        [^title_ref] -> {defs[title], defs}
        _ -> Map.pop(defs, title)
      end

    if map_size(defs) > 0 do
      Map.put(root, :"$defs", defs)
    else
      root
    end
  end

  defp bfs_from_ecto_schema([], _seen_schemas), do: []

  defp bfs_from_ecto_schema([ecto_schema | rest], seen_schemas)
       when is_ecto_schema(ecto_schema) do
    seen_schemas = MapSet.put(seen_schemas, ecto_schema)

    ignored =
      if function_exported?(ecto_schema, :__mentor_ignored_fields__, 0) do
        ecto_schema.__mentor_ignored_fields__()
      else
        []
      end

    # Create a new struct instance to detect fields with defaults
    struct_instance = struct(ecto_schema)
    default? = fn field -> not is_nil(Map.get(struct_instance, field)) end

    properties =
      :fields
      |> ecto_schema.__schema__()
      |> Enum.reject(&(&1 in ignored))
      |> Map.new(fn field ->
        type = ecto_schema.__schema__(:type, field)
        value = for_type(type, with_default?: default?.(field))

        {field, value}
      end)

    associations =
      :associations
      |> ecto_schema.__schema__()
      |> Enum.map(&ecto_schema.__schema__(:association, &1))
      |> Enum.filter(&(&1.relationship != :parent))
      |> Map.new(fn association ->
        field = association.field
        title = title_for(association.related)

        value =
          if association.cardinality == :many do
            %{
              items: %{"$ref": "#/$defs/#{title}"},
              type: if(default?.(field), do: ["array", "null"], else: "array")
            }
          else
            %{"$ref": "#/$defs/#{title}"}
          end

        {field, value}
      end)

    properties = Map.merge(properties, associations)

    required =
      properties
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    title = title_for(ecto_schema)

    associated_schemas =
      :associations
      |> ecto_schema.__schema__()
      |> Enum.map(&ecto_schema.__schema__(:association, &1).related)
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    embedded_schemas =
      :embeds
      |> ecto_schema.__schema__()
      |> Enum.map(&ecto_schema.__schema__(:embed, &1).related)
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    rest =
      rest
      |> Enum.concat(associated_schemas)
      |> Enum.concat(embedded_schemas)
      |> Enum.uniq()

    schema =
      %{
        title: title,
        type: "object",
        required: required,
        properties: properties,
        additionalProperties: false
      }

    [schema | bfs_from_ecto_schema(rest, seen_schemas)]
  end

  defp bfs_from_ecto_schema([ecto_types | rest], seen_schemas) when is_ecto_types(ecto_types) do
    properties =
      for {field, type} <- ecto_types, into: %{} do
        {field, for_type(type)}
      end

    required = properties |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

    embedded_schemas =
      for {_field, {:parameterized, {Ecto.Embedded, %{related: related}}}} <-
            ecto_types,
          is_ecto_schema(related) do
        related
      end

    rest =
      rest
      |> Enum.concat(embedded_schemas)
      |> Enum.uniq()
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    schema =
      %{
        title: "root",
        type: "object",
        required: required,
        properties: properties,
        additionalProperties: false
      }

    [schema | bfs_from_ecto_schema(rest, seen_schemas)]
  end

  defp title_for(ecto_schema) when is_ecto_schema(ecto_schema) do
    ecto_schema |> to_string() |> String.split(".") |> List.last()
  end

  # Find all values in a map or list that match a predicate
  defp find_all_values(map, pred) when is_map(map) do
    Enum.flat_map(map, fn
      {key, val} -> if pred.({key, val}), do: [val], else: find_all_values(val, pred)
    end)
  end

  defp find_all_values(list, pred) when is_list(list) do
    Enum.flat_map(list, fn
      val ->
        find_all_values(val, pred)
    end)
  end

  defp find_all_values(_, _pred), do: []

  defp for_type(field, opts \\ [with_default?: false])

  defp for_type(type, with_default?: true) do
    case for_type(type) do
      %{type: type} = def -> %{def | type: [type, "null"]}
      def -> def
    end
  end

  defp for_type(:id, _opts), do: %{type: "integer"}
  defp for_type(:binary_id, _opts), do: %{type: "string"}
  defp for_type(:integer, _opts), do: %{type: "integer"}
  defp for_type(:float, _opts), do: %{type: "number"}
  defp for_type(:boolean, _opts), do: %{type: "boolean"}
  defp for_type(:string, _opts), do: %{type: "string"}
  defp for_type({:array, type}, _opts), do: %{type: "array", items: for_type(type)}
  defp for_type(:map, _opts), do: %{type: "object", additionalProperties: %{type: "string"}}
  defp for_type({:map, type}, _opts), do: %{type: "object", additionalProperties: for_type(type)}

  defp for_type(:decimal, _opts), do: %{type: "number"}
  defp for_type(:date, _opts), do: %{type: "string"}
  defp for_type(:time, _opts), do: %{type: "string"}

  defp for_type(:time_usec, _opts), do: %{type: "string"}

  defp for_type(:naive_datetime, _opts), do: %{type: "string"}
  defp for_type(:naive_datetime_usec, _opts), do: %{type: "string"}
  defp for_type(:utc_datetime, _opts), do: %{type: "string"}
  defp for_type(:utc_datetime_usec, _opts), do: %{type: "string"}

  defp for_type({:parameterized, {Ecto.Embedded, %{cardinality: :many, related: related}}}, _opts)
       when is_ecto_schema(related) do
    title = title_for(related)

    %{
      items: %{"$ref": "#/$defs/#{title}"},
      type: "array"
    }
  end

  defp for_type({:parameterized, {Ecto.Embedded, %{cardinality: :many, related: related}}}, _opts)
       when is_ecto_types(related) do
    properties =
      for {field, type} <- related, into: %{} do
        {field, for_type(type)}
      end

    required = properties |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

    %{
      items: %{
        type: "object",
        required: required,
        properties: properties
      },
      type: "array"
    }
  end

  defp for_type({:parameterized, {Ecto.Embedded, %{cardinality: :one, related: related}}}, _opts)
       when is_ecto_schema(related) do
    %{"$ref": "#/$defs/#{title_for(related)}"}
  end

  defp for_type({:parameterized, {Ecto.Embedded, %{cardinality: :one, related: related}}}, _opts)
       when is_ecto_types(related) do
    properties =
      for {field, type} <- related, into: %{} do
        {field, for_type(type)}
      end

    required = properties |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

    %{
      type: "object",
      required: required,
      properties: properties
    }
  end

  defp for_type({:parameterized, {Ecto.Enum, %{mappings: mappings}}}, _opts) do
    %{
      type: "string",
      enum: Keyword.keys(mappings)
    }
  end

  defp for_type(mod, _opts) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :to_json_schema, 0) do
      mod.to_json_schema()
    else
      raise "Unsupported type: #{inspect(mod)}, please implement `to_json_schema/0` via `Mentor.Ecto.Type` behaviour"
    end
  end
end
