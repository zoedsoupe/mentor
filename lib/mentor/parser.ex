defmodule Mentor.Parser do
  @moduledoc """
  A minimal "Markdown" parser to extract structured field documentation from @moduledoc.
  Used for `Mentor.Ecto.Schema`.

  Supports:
    - `## Fields` section (case-sensitive)
    - Field definitions in the format: `- \`field_name\`: Description`
    - Multiline descriptions, which are joined as a single paragraph
  """

  @type field :: {:field, name :: atom, desc :: String.t()}
  @type section :: {:section, name :: String.t(), fields :: [field]}
  @type ast :: [section]

  @doc """
  Parses a Markdown string into an AST-like structure.

  ## Supported Syntax
    - Sections: `## Section Title`
    - Field Definitions: `- \`field_name\`: Description`
    - Multiline field descriptions (joined as a single paragraph)

  ## Returns
    - `{:ok, ast}` on success
    - `{:error, reason}` on invalid syntax

  ## Examples

      iex> markdown = \"""
      ...> ## Fields
      ...> - `name`: The user's name.
      ...> - `age`: The user's age
      ...> that defines the user age
      ...> \"""
      iex> Mentor.Parser.run(markdown)
      [{:section, "Fields", [{:field, :name, "The user's name."}, {:field, :age, "The user's age that defines the user age"}]}]
  """
  @spec run(String.t()) :: ast
  def run(markdown) do
    markdown
    |> String.split("\n", trim: true)
    |> Enum.reduce_while([], &process_line/2)
    |> Enum.map(fn {:section, title, fields} ->
      {:section, title, Enum.reverse(fields)}
    end)
    |> Enum.reverse()
  end

  defp process_line(<<"## ", "Fields">>, acc) do
    {:cont, [{:section, "Fields", []} | acc]}
  end

  # Stop processing when a new section starts after "Fields"
  defp process_line(<<"## ", _rest::binary>>, [{:section, "Fields", _fields} | _acc] = acc) do
    {:halt, acc}
  end

  defp process_line(<<"- `", rest::binary>>, [{:section, title, fields} | acc]) do
    [field, desc] = String.split(rest, "`: ", parts: 2)
    {:cont, [{:section, title, [{:field, String.to_atom(field), desc} | fields]} | acc]}
  end

  # Append multiline description to the last field
  defp process_line(line, [{:section, title, [{:field, field, desc} | fields]} | acc])
       when line != "" do
    {:field, field, desc <> " " <> String.trim(line)}
    |> then(&{:cont, [{:section, title, [&1 | fields]} | acc]})
  end

  defp process_line(_, acc), do: {:cont, acc}
end
