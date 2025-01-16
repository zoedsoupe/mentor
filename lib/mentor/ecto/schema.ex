defmodule Mentor.Ecto.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @before_compile Mentor.Ecto.Schema
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

  def validate(schema, %{} = data) do
    struct(schema)
    |> schema.changeset(data)
    |> Ecto.Changeset.apply_action(:parse)
  end
end
