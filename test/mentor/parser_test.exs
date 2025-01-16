defmodule Mentor.ParserTest do
  use ExUnit.Case, async: true

  alias Mentor.Parser

  doctest Mentor.Parser

  describe "run/1" do
    test "parses a simple valid markdown with single-line descriptions" do
      markdown = """
      ## Fields

      - `name`: The user's name.
      - `age`: The user's age.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."},
                  {:field, :age, "The user's age."}
                ]}
             ]
    end

    test "parses multiline field descriptions correctly" do
      markdown = """
      ## Fields

      - `name`: The user's name.
      - `age`: The user's age
      that defines the user age.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."},
                  {:field, :age, "The user's age that defines the user age."}
                ]}
             ]
    end

    test "ignores unrelated markdown outside ## Fields" do
      markdown = """
      # Title

      Some introductory text.

      ## Fields

      - `name`: The user's name.

      ## Another Section

      This section is unrelated.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."}
                ]}
             ]
    end

    test "handles multiple sections with only the relevant section parsed" do
      markdown = """
      ## Fields

      - `name`: The user's name.

      ## Other Section

      - `irrelevant`: This is ignored.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."}
                ]}
             ]
    end

    test "parses markdown with no fields gracefully" do
      markdown = """
      ## Fields
      """

      assert Parser.run(markdown) == [
               {:section, "Fields", []}
             ]
    end

    test "returns an empty list for completely unrelated markdown" do
      markdown = """
      # Title

      This document has no relevant sections.
      """

      assert Parser.run(markdown) == []
    end

    test "handles trailing empty lines gracefully" do
      markdown = """
      ## Fields

      - `name`: The user's name.

      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."}
                ]}
             ]
    end

    test "parses complex multiline descriptions with empty lines" do
      markdown = """
      ## Fields

      - `name`: The user's name.
      - `age`: The user's age
      that defines the user age
      and ensures validity.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :name, "The user's name."},
                  {:field, :age, "The user's age that defines the user age and ensures validity."}
                ]}
             ]
    end

    test "handles descriptions with embedded newlines as a single paragraph" do
      markdown = """
      ## Fields

      - `description`: This is a field
      with a long description
      that spans multiple lines.

      - `short`: Single-line description.
      """

      assert Parser.run(markdown) == [
               {:section, "Fields",
                [
                  {:field, :description,
                   "This is a field with a long description that spans multiple lines."},
                  {:field, :short, "Single-line description."}
                ]}
             ]
    end
  end
end
