if Code.ensure_loaded?(Peri) do
  defmodule Mentor.Peri.Schema do
    @moduledoc """
    Implementation of the Mentor.Schema behaviour for Peri schemas.

    This module provides integration between Peri schemas and Mentor, allowing
    developers to use Peri's powerful validation system with LLM output generation.
    """

    @behaviour Mentor.Schema

    @impl Mentor.Schema
    def validate(schema, data) do
      case Peri.validate(schema, data) do
        {:ok, validated_data} ->
          {:ok, validated_data}

        {:error, errors} ->
          formatted_errors = format_peri_errors(errors)
          {:error, %{errors: formatted_errors}}
      end
    end

    @impl Mentor.Schema
    def definition(schema) when is_map(schema) do
      Enum.map(schema, fn {key, type} -> {key, extract_base_type(type)} end)
    end

    def definition(schema) do
      [{:value, extract_base_type(schema)}]
    end

    def to_json_schema(schema) do
      convert_type_to_json_schema(schema)
    end

    def generate_field_descriptions(schema) when is_map(schema) do
      schema
      |> Enum.map(fn {key, type} -> {key, describe_type(type)} end)
      |> Enum.into(%{})
    end

    def generate_field_descriptions(schema) do
      %{"value" => describe_type(schema)}
    end

    defp format_peri_errors(errors) when is_list(errors) do
      Enum.map(errors, &format_single_error/1)
    end

    defp format_single_error(%Peri.Error{} = error) do
      path = error_path_to_string(error)
      %{field: path, message: error.message}
    end

    defp format_single_error(error) when is_binary(error) do
      %{field: "root", message: error}
    end

    defp error_path_to_string(%Peri.Error{path: path}) when is_list(path) do
      path
      |> Enum.map_join(".", &to_string/1)
      |> case do
        "" -> "root"
        path_str -> path_str
      end
    end

    defp error_path_to_string(%Peri.Error{key: key}) when not is_nil(key) do
      to_string(key)
    end

    defp error_path_to_string(_), do: "root"

    defp required?({:required, _}), do: true
    defp required?(_), do: false

    defp convert_type_to_json_schema({:required, type}) do
      convert_type_to_json_schema(type)
    end

    defp convert_type_to_json_schema(:string), do: %{"type" => "string"}
    defp convert_type_to_json_schema(:integer), do: %{"type" => "integer"}
    defp convert_type_to_json_schema(:float), do: %{"type" => "number"}
    defp convert_type_to_json_schema(:boolean), do: %{"type" => "boolean"}
    defp convert_type_to_json_schema(:atom), do: %{"type" => "string"}
    defp convert_type_to_json_schema(:any), do: %{}

    defp convert_type_to_json_schema(:date) do
      %{"type" => "string", "format" => "date"}
    end

    defp convert_type_to_json_schema(:time) do
      %{"type" => "string", "format" => "time"}
    end

    defp convert_type_to_json_schema(:datetime) do
      %{"type" => "string", "format" => "date-time"}
    end

    defp convert_type_to_json_schema(:naive_datetime) do
      %{"type" => "string", "format" => "date-time"}
    end

    defp convert_type_to_json_schema(:duration) do
      %{"type" => "string", "format" => "duration"}
    end

    defp convert_type_to_json_schema({:string, {:regex, %Regex{source: pattern}}}) do
      %{"type" => "string", "pattern" => pattern}
    end

    defp convert_type_to_json_schema({:string, {:eq, value}}) do
      %{"type" => "string", "const" => value}
    end

    defp convert_type_to_json_schema({:string, {:min, min}}) do
      %{"type" => "string", "minLength" => min}
    end

    defp convert_type_to_json_schema({:string, {:max, max}}) do
      %{"type" => "string", "maxLength" => max}
    end

    defp convert_type_to_json_schema({:integer, constraint}) do
      convert_numeric_constraint("integer", constraint)
    end

    defp convert_type_to_json_schema({:float, constraint}) do
      convert_numeric_constraint("number", constraint)
    end

    defp convert_type_to_json_schema({:enum, values}) when is_list(values) do
      %{"enum" => values}
    end

    defp convert_type_to_json_schema({:enum, values, type}) when is_list(values) do
      base = convert_type_to_json_schema(type)
      Map.put(base, "enum", values)
    end

    defp convert_type_to_json_schema({:list, item_type}) do
      %{
        "type" => "array",
        "items" => convert_type_to_json_schema(item_type)
      }
    end

    defp convert_type_to_json_schema({:map, value_type}) do
      %{
        "type" => "object",
        "additionalProperties" => convert_type_to_json_schema(value_type)
      }
    end

    defp convert_type_to_json_schema({:map, _key_type, value_type}) do
      %{
        "type" => "object",
        "additionalProperties" => convert_type_to_json_schema(value_type)
      }
    end

    defp convert_type_to_json_schema({:tuple, types}) when is_list(types) do
      %{
        "type" => "array",
        "prefixItems" => Enum.map(types, &convert_type_to_json_schema/1),
        "minItems" => length(types),
        "maxItems" => length(types)
      }
    end

    defp convert_type_to_json_schema({:literal, value}) do
      %{"const" => value}
    end

    defp convert_type_to_json_schema({:either, {type1, type2}}) do
      %{"oneOf" => [convert_type_to_json_schema(type1), convert_type_to_json_schema(type2)]}
    end

    defp convert_type_to_json_schema({:oneof, types}) when is_list(types) do
      %{"oneOf" => Enum.map(types, &convert_type_to_json_schema/1)}
    end

    defp convert_type_to_json_schema({type, {:default, _default}}) do
      convert_type_to_json_schema(type)
    end

    defp convert_type_to_json_schema({:custom, _fun}) do
      %{}
    end

    defp convert_type_to_json_schema({:cond, _condition, _true_type, _false_type}) do
      %{}
    end

    defp convert_type_to_json_schema({:dependent, _callback}) do
      %{}
    end

    defp convert_type_to_json_schema({:transform, _mapper}) do
      %{}
    end

    defp convert_type_to_json_schema(nested_schema) when is_map(nested_schema) do
      case Peri.validate_schema(nested_schema) do
        {:ok, _} ->
          properties =
            Map.new(nested_schema, fn {key, type} ->
              {to_string(key), convert_type_to_json_schema(type)}
            end)

          required =
            nested_schema
            |> Enum.filter(fn {_key, type} -> required?(type) end)
            |> Enum.map(fn {key, _type} -> to_string(key) end)

          base = %{
            "type" => "object",
            "properties" => properties,
            "additionalProperties" => false
          }

          if Enum.empty?(required), do: base, else: Map.put(base, "required", required)

        _ ->
          %{}
      end
    end

    defp convert_type_to_json_schema(_unknown), do: %{}

    defp convert_numeric_constraint(json_type, {:eq, value}) do
      %{"type" => json_type, "const" => value}
    end

    defp convert_numeric_constraint(json_type, {:neq, value}) do
      %{"type" => json_type, "not" => %{"const" => value}}
    end

    defp convert_numeric_constraint(json_type, {:gt, value}) do
      %{"type" => json_type, "exclusiveMinimum" => value}
    end

    defp convert_numeric_constraint(json_type, {:gte, value}) do
      %{"type" => json_type, "minimum" => value}
    end

    defp convert_numeric_constraint(json_type, {:lt, value}) do
      %{"type" => json_type, "exclusiveMaximum" => value}
    end

    defp convert_numeric_constraint(json_type, {:lte, value}) do
      %{"type" => json_type, "maximum" => value}
    end

    defp convert_numeric_constraint(json_type, {:range, {min, max}}) do
      %{"type" => json_type, "minimum" => min, "maximum" => max}
    end

    defp describe_type({:required, type}) do
      "Required #{describe_base_type(type)}"
    end

    defp describe_type({type, {:default, default}}) do
      "Optional #{describe_base_type(type)} (default: #{inspect(default)})"
    end

    defp describe_type(type) do
      "Optional #{describe_base_type(type)}"
    end

    defp describe_base_type(:string), do: "string"
    defp describe_base_type(:integer), do: "integer"
    defp describe_base_type(:float), do: "number"
    defp describe_base_type(:boolean), do: "boolean"
    defp describe_base_type(:atom), do: "atom (as string)"
    defp describe_base_type(:date), do: "date (ISO 8601 format)"
    defp describe_base_type(:time), do: "time (ISO 8601 format)"
    defp describe_base_type(:datetime), do: "datetime (ISO 8601 format)"
    defp describe_base_type(:naive_datetime), do: "datetime without timezone"
    defp describe_base_type(:duration), do: "duration (ISO 8601 format)"

    defp describe_base_type({:string, {:regex, %Regex{source: pattern}}}) do
      "string matching pattern: #{pattern}"
    end

    defp describe_base_type({:string, {:min, min}}) do
      "string with minimum length #{min}"
    end

    defp describe_base_type({:string, {:max, max}}) do
      "string with maximum length #{max}"
    end

    defp describe_base_type({:integer, constraint}) do
      "integer #{describe_numeric_constraint(constraint)}"
    end

    defp describe_base_type({:float, constraint}) do
      "number #{describe_numeric_constraint(constraint)}"
    end

    defp describe_base_type({:enum, values}) do
      "one of: #{inspect(values)}"
    end

    defp describe_base_type({:list, item_type}) do
      "array of #{describe_base_type(item_type)} elements"
    end

    defp describe_base_type({:map, _value_type}) do
      "object with string keys"
    end

    defp describe_base_type({:tuple, types}) when is_list(types) do
      types_desc = Enum.map_join(types, ", ", &describe_base_type/1)
      "tuple with elements: [#{types_desc}]"
    end

    defp describe_base_type({:literal, value}) do
      "exactly: #{inspect(value)}"
    end

    defp describe_base_type({:either, {type1, type2}}) do
      "either #{describe_base_type(type1)} or #{describe_base_type(type2)}"
    end

    defp describe_base_type({:oneof, types}) when is_list(types) do
      options = Enum.map_join(types, " or ", &describe_base_type/1)
      "one of: #{options}"
    end

    defp describe_base_type(schema) when is_map(schema) do
      "nested object"
    end

    defp describe_base_type(_) do
      "value"
    end

    defp describe_numeric_constraint({:eq, value}), do: "equal to #{value}"
    defp describe_numeric_constraint({:neq, value}), do: "not equal to #{value}"
    defp describe_numeric_constraint({:gt, value}), do: "greater than #{value}"
    defp describe_numeric_constraint({:gte, value}), do: "greater than or equal to #{value}"
    defp describe_numeric_constraint({:lt, value}), do: "less than #{value}"
    defp describe_numeric_constraint({:lte, value}), do: "less than or equal to #{value}"
    defp describe_numeric_constraint({:range, {min, max}}), do: "between #{min} and #{max}"

    defp extract_base_type({:required, type}), do: extract_base_type(type)
    defp extract_base_type({type, _constraint}) when is_atom(type), do: type
    defp extract_base_type(type) when is_atom(type), do: type
    defp extract_base_type({:list, _}), do: :list
    defp extract_base_type({:map, _}), do: :map
    defp extract_base_type({:map, _, _}), do: :map
    defp extract_base_type({:tuple, _}), do: :tuple
    defp extract_base_type({:enum, _, type}), do: extract_base_type(type)
    defp extract_base_type({:enum, _}), do: :enum
    defp extract_base_type({:literal, _}), do: :any
    defp extract_base_type({:either, _}), do: :any
    defp extract_base_type({:oneof, _}), do: :any
    defp extract_base_type(_), do: :any
  end
end
