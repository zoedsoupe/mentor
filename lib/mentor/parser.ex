defmodule Mentor.Parser do
  @moduledoc """
  Responsible for verifying if all schema fields are present in the documentation either
  in the `@moduledoc` attribute or as the return of the `llm_description/0` callback.
  """

  @doc """
  Verifies the provided markdown to extract field names that are missing descriptions.

  ## Parameters
  - `markdown`: The markdown string to parse.
  - `expected_fields`: A list of atoms or strings representing the expected field names.

  ## Examples
      iex> markdown = \"""
      ...> ## Fields
      ...>
      ...> - `name`: The user's name.
      ...> - `age`: The user's age.
      ...> - `offices_held`:
      ...>   - `office`: The political office name
      ...>   - `from_date`: Start date
      ...> \"""
      iex> Mentor.Parser.run(markdown, ["name", "age", "offices_held.office", "offices_held.from_date"])
      []

      iex> markdown = \"""
      ...> ## Fields
      ...>
      ...> - name: The user's name.
      ...> - offices_held:
      ...>   - office: The political office
      ...> \"""
      iex> Mentor.Parser.run(markdown, [:name, "offices_held.office", "offices_held.from_date"])
      ["offices_held.from_date"]
  """
  def run(markdown, expected) when is_binary(markdown) and is_list(expected) do
    expected
    |> Enum.map(&to_string/1)
    |> Enum.flat_map(&String.split(&1, ".", trim: true))
    |> Enum.reduce([], fn field, missing ->
      if markdown =~ field, do: missing, else: [field | missing]
    end)
    |> Enum.reverse()
  end
end
