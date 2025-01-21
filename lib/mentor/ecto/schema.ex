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
  """

  import Mentor.Schema

  @behaviour Mentor.Schema

  @callback changeset(Ecto.Schema.t(), map) :: Ecto.Changeset.t()
  @callback llm_description :: String.t()

  @optional_callbacks llm_description: 0

  defmacro __using__(_opts) do
    quote do
      @before_compile Mentor.Ecto.Schema
      @after_compile Mentor.Ecto.Schema
      @behaviour Mentor.Ecto.Schema
    end
  end

  defmacro __after_compile__(env, _bytecode) do
    mod = env.module
    schema = definition(mod)
    custom? = function_exported?(mod, :llm_description, 0)

    doc =
      if custom?,
        do: mod.llm_description(),
        else: mod.__mentor_schema_documentation__()

    keys = Enum.map(schema, &elem(&1, 0))
    parse_llm_description!(doc, keys, env)
    if is_nil(doc), do: missing_documentation!(env, keys)
  end

  defmacro __before_compile__(env) do
    doc =
      case Module.get_attribute(env.module, :moduledoc) do
        {_line, doc} -> doc
        _ -> nil
      end

    quote do
      def __mentor_schema_documentation__, do: unquote(doc)
    end
  end

  @impl true
  def definition(module) when is_atom(module) do
    fields = module.__schema__(:fields) ++ module.__schema__(:virtual_fields)

    # Get field types from schema
    field_types =
      fields
      |> Enum.map(fn field ->
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
    struct(schema)
    |> schema.changeset(data)
    |> Ecto.Changeset.apply_action(:parse)
  end
end
