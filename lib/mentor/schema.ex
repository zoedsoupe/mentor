defmodule Mentor.Schema do
  @moduledoc """
  Defines the `Mentor.Schema` behaviour for integrating various data structures
  with the Mentor framework. This behaviour allows for the creation of schema
  adapters, enabling Mentor to work seamlessly with different data representations
  such as `Ecto` schemas, raw structs, and maps.

  Modules implementing this behaviour are required to define the following callbacks:

    * `c:definition/1` - Specifies the schema definition, detailing the fields and their types.
    * `c:validate/2` - Validates the provided data against the schema, returning the validated structure or an error term.

  Additionally, this module provides functions to parse and validate field documentation, ensuring that all fields are properly documented.
  """

  @type source :: module | map
  @type field :: {name :: atom, type :: atom}
  @type t :: struct | map

  @callback definition(source) :: list(field)
  @callback validate(source, data :: map) :: {:ok, t} | {:error, term}

  @doc """
  Parses the given documentation string to ensure that all fields in the schema
  are properly documented. If any fields are missing documentation, a compile-time
  error is raised.

  ## Parameters

    * `doc` - The documentation string to parse.
    * `schema` - A list of fields expected in the schema.
    * `env` - The current macro environment.

  ## Examples

      iex> Mentor.Schema.parse_llm_description!(doc_string, [:name, :age], __ENV__)
      :ok

  """
  @spec parse_llm_description!(binary, list(atom), Macro.Env.t()) :: :ok
  def parse_llm_description!(doc, schema, %Macro.Env{} = env)
      when is_binary(doc) and is_list(schema) do
    case Mentor.Parser.run(doc, schema) do
      [] -> :ok
      missing_fields -> missing_documentation!(env, missing_fields)
    end
  end

  @doc """
  Raises a compile-time error indicating which fields are missing documentation
  in the `@moduledoc` attribute or the `llm_description/0` callback.

  ## Parameters

    * `env` - The current macro environment.
    * `fields` - A list of fields missing documentation.

  ## Examples

      iex> Mentor.Schema.missing_documentation!(__ENV__, [:name, :age])
      ** (CompileError) The following fields are missing documentation either in `@moduledoc` attribute or `llm_description/0` callback: [:name, :age]

  """
  def missing_documentation!(%Macro.Env{} = env, fields) when is_list(fields) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description:
        "The following fields are missing documentation either in `@moduledoc` attribute or `llm_description/0` callback: #{inspect(fields, pretty: true)}"
  end
end
