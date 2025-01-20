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
  """

  @callback changeset(Ecto.Schema.t(), map) :: Ecto.Changeset.t()

  defmacro __using__(_opts) do
    quote do
      @before_compile Mentor.Ecto.Schema
      @behaviour Mentor.Ecto.Schema
    end
  end

  defmacro __before_compile__(env) do
    schema =
      env.module
      |> Module.get_attribute(:ecto_fields, [])
      |> Enum.map(fn {field, _} -> field end)

    {_line, doc} = Module.get_attribute(env.module, :moduledoc)

    case Mentor.Parser.run(doc || "") do
      [{:section, "Fields", fields}] ->
        fields
        |> Enum.reject(fn {:field, name, _} -> name in schema end)
        |> Enum.map(fn {:field, name, _} -> name end)
        |> then(&missing_documentation(env, &1))

      [] ->
        missing_documentation(env, schema)
    end

    quote do
      def __mentor_schema_documentation__, do: unquote(doc)
    end
  end

  defp missing_documentation(_, []), do: nil

  defp missing_documentation(env, fields) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description:
        "The following fields are missing documentation in @moduledoc: #{inspect(fields, pretty: true)}"
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
  @spec validate(module, map) :: {:ok, struct} | {:error, Ecto.Changeset.t()}
  def validate(schema, %{} = data) do
    struct(schema)
    |> schema.changeset(data)
    |> Ecto.Changeset.apply_action(:parse)
  end
end
