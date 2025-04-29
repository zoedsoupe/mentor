defmodule Mentor.Ecto.Schema do
  @moduledoc """
  Provides functionality to integrate Ecto schemas with the Mentor framework, ensuring that schemas include comprehensive field documentation.

  This module defines a behaviour that requires implementing a `changeset/2` function and utilizes compile-time hooks to verify that all fields in the schema are documented in the module's `@moduledoc`.

  ## Usage

  To use `Mentor.Ecto.Schema` in your Ecto schema module:

      defmodule MyApp.Schema do
        use Ecto.Schema
        use Mentor.Ecto.Schema

        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          field :name, :string
          field :age, :integer
        end

        @impl true
        def changeset(%__MODULE__{} = source, %{} = attrs) do
          source
          |> cast(attrs, [:name, :age])
          |> validate_required([:name, :age])
          |> validate_number(:age, less_than: 100, greater_than: 0)
        end
      end

  Ensure that your module's `@moduledoc` includes a "Fields" section documenting each field:

      @moduledoc \"""
      Schema representing a person.

      ## Fields

      - `name`: The name of the person.
      - `age`: The age of the person.
      \"""

  ## Custom LLM description

  If you don't wanna or can't rely on `@moduledoc` to descrive the LLM prompt for your schema, you can alternatively provide a `llm_description/0` callback into you schema module that returns a string that represents the prompt it self, like:

      @impl true
      def llm_description do
        \"""
        ## Fields

        - `name`: it should be a valid string name for humans
        - `age`: it should be a reasonable age number for a human being
        \"""
      end

  ## Ignored fields

  Sometimes you wanna use an Ecto schema field only for internal logic or even have different changesets functions that can cast on different set of fields and for so you would like to avoid to send these fields to the LLM and avoid the strictness of filling the description for these fields in the `@moduledoc`.

  In this case you can pass an additional option while using this module, called `ignored_fields`, passing a list of atoms with the fields names to be ignored, for instance:

      defmodule MyApp.Schema do
        use Ecto.Schema
        use Mentor.Ecto.Schema, ignored_fields: [:timestamps]

        import Ecto.Changeset

        @timestamps_opts [inserted_at: :created_at]

        @primary_key false
        embedded_schema do
          field :name, :string
          field :age, :integer

          timestamps()
        end

        @impl true
        def changeset(%__MODULE__{} = source, %{} = attrs) do
          source
          |> cast(attrs, [:name, :age])
          |> validate_required([:name, :age])
          |> validate_number(:age, less_than: 100, greater_than: 0)
        end
      end

  One so common use case for this option, as can be seen on the aboce example are the timestamps fields that Ecto generate, so for this special case you can inform `:timestamps` as an ignored field to ignore both `[:inserted_at, :updated_at]`, even if you define custom aliases for it with the `@timestamps_opts` attribute, like `:created_at`.

  You can also pass partial timestamps fields to be ignored, like only ignore `:created_at` or `:updated_at`.

  > ### Warning {: .warning}
  >
  > Defining timestamps aliases with the macro `timestamps/1` inside the schema itself, aren't supported, since i didn't discover how to get this data from on compile time to filter as ignored fields, sou you can either define these options as the attribute as said above, or pass the individual aliases names into the `ignored_fields` options.
  """

  @behaviour Mentor.Schema

  import Mentor.Schema

  @callback changeset(Ecto.Schema.t(), map) :: Ecto.Changeset.t()
  @callback llm_description :: String.t()

  @optional_callbacks llm_description: 0

  defmacro __using__(opts \\ []) do
    ignored = opts[:ignored_fields] || []

    quote do
      @before_compile Mentor.Ecto.Schema
      @after_compile Mentor.Ecto.Schema
      @behaviour Mentor.Ecto.Schema

      @doc false
      def __mentor_ignored_fields__, do: unquote(ignored)
    end
  end

  defmacro __after_compile__(env, _bytecode) do
    mod = env.module
    schema = definition(mod)
    custom? = function_exported?(mod, :llm_description, 0)

    ignored =
      mod.__mentor_ignored_fields__()
      |> then(&maybe_ignore_timestamps(mod, &1))
      |> Enum.filter(&Function.identity/1)

    doc =
      if custom?,
        do: mod.llm_description(),
        else: mod.__mentor_schema_documentation__()

    keys = Enum.map(schema, &elem(&1, 0)) |> Enum.reject(&(&1 in ignored))
    parse_llm_description!(doc, keys, env)
    if String.length(doc) < 1, do: missing_documentation!(env, keys)
  end

  defmacro __before_compile__(env) do
    doc =
      case Module.get_attribute(env.module, :moduledoc) do
        {_line, doc} -> doc
        _ -> ""
      end

    quote do
      @doc false
      @spec __mentor_schema_documentation__ :: String.t()
      def __mentor_schema_documentation__, do: unquote(doc)
    end
  end

  defp maybe_ignore_timestamps(mod, ignored) do
    timestamps_opts =
      mod
      |> Module.get_attribute(:timestamps_opts)
      |> then(fn opts -> if opts == [], do: nil, else: opts end)

    cond do
      is_nil(timestamps_opts) and :timestamps in ignored ->
        ignored ++ [:inserted_at, :updated_at]

      not is_nil(timestamps_opts) and :timestamps in ignored ->
        [
          Keyword.get_lazy(timestamps_opts, :inserted_at, fn -> :inserted_at end),
          Keyword.get_lazy(timestamps_opts, :updated_at, fn -> :updated_at end)
          | ignored
        ]

      not is_nil(timestamps_opts) ->
        [timestamps_opts[:inserted_at], timestamps_opts[:inserted_at] | ignored]

      true ->
        ignored
    end
  end

  @impl true
  def definition(module) when is_atom(module) do
    fields = module.__schema__(:fields) ++ module.__schema__(:virtual_fields)

    # Get field types from schema
    field_types =
      Enum.map(fields, fn field ->
        field_type = get_field_type(module, field)
        {field, field_type}
      end)

    # Get embedded schemas
    embeds = module.__schema__(:embeds)
    embedded_fields = get_embedded_fields(module, embeds)

    # Get associations
    associations = module.__schema__(:associations)
    association_fields = get_association_fields(module, associations)

    # Combine all fields
    field_types ++ embedded_fields ++ association_fields
  end

  # Handle regular field types
  defp get_field_type(module, field) do
    case module.__schema__(:type, field) do
      # Default to string for virtual fields
      nil -> :string
      {:parameterized, Ecto.Enum, %{mappings: mappings}} -> {:enum, Map.keys(mappings)}
      {:array, type} -> {:array, type}
      {:map, type} -> {:map, type}
      type -> type
    end
  end

  # Handle embedded schemas
  defp get_embedded_fields(module, embeds) do
    Enum.flat_map(embeds, &get_embedded_field(module, &1))
  end

  defp get_embedded_field(module, embed) do
    embed_schema = module.__schema__(:embed, embed)
    embed_module = embed_schema.related

    if embed_schema.cardinality == :one do
      embed_module
      |> definition()
      |> Enum.map(fn {field, type} -> {"#{embed}.#{field}", type} end)
    else
      embed_module
      |> definition()
      |> Enum.map(fn {field, type} -> {"#{embed}.#{field}", {:array, type}} end)
    end
  end

  # Handle associations
  defp get_association_fields(module, associations) do
    Enum.flat_map(associations, fn assoc ->
      assoc_schema = module.__schema__(:association, assoc)
      related_module = assoc_schema.related

      # Get the primary key of the related module
      related_fields =
        related_module
        |> definition()
        |> Enum.map(fn {field, type} ->
          {"#{assoc}.#{field}", get_association_type(assoc_schema, type)}
        end)

      # Add the association's foreign key if it exists
      case assoc_schema.owner_key do
        nil -> related_fields
        key -> [{key, :integer} | related_fields]
      end
    end)
  end

  # Determine the type based on association cardinality
  defp get_association_type(assoc_schema, type) do
    case assoc_schema.cardinality do
      :one -> type
      :many -> {:array, type}
    end
  end

  @doc """
  Validates the given data against the specified schema by applying the schema's `changeset/2` function.

  ## Parameters

  - `schema`: The schema module implementing the `Mentor.Ecto.Schema` behaviour.
  - `data`: A map containing the data to be validated.

  ## Returns

  - `{:ok, struct}`: If the data is valid and conforms to the schema.
  - `{:error, changeset}`: If the data is invalid, returns the changeset with errors.

  ## Examples

      iex> data = %{"name" => "Alice", "age" => 30}
      iex> Mentor.Ecto.Schema.validate(MyApp.Schema, data)
      {:ok, %MyApp.Schema{name: "Alice", age: 30}}

      iex> invalid_data = %{"name" => "Alice", "age" => 150}
      iex> Mentor.Ecto.Schema.validate(MyApp.Schema, invalid_data)
      {:error, %Ecto.Changeset{errors: [age: {"must be less than 100", [validation: :number, less_than: 100]}]}}
  """
  @impl true
  def validate(schema, %{} = data) do
    schema
    |> struct()
    |> schema.changeset(data)
    |> Ecto.Changeset.apply_action(:parse)
  end
end
