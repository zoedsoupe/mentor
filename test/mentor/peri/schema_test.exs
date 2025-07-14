defmodule Mentor.Peri.SchemaTest do
  use ExUnit.Case, async: true

  alias Mentor.Peri.Schema, as: MentorPeri

  describe "validate/2" do
    test "validates map schemas successfully" do
      schema = %{
        name: {:required, :string},
        age: {:integer, {:gte, 0}},
        email: {:string, {:regex, ~r/@/}}
      }

      valid_data = %{
        "name" => "John Doe",
        "age" => 30,
        "email" => "john@example.com"
      }

      assert {:ok, validated} = MentorPeri.validate(schema, valid_data)
      assert validated == %{name: "John Doe", age: 30, email: "john@example.com"}
    end

    test "returns errors for invalid data" do
      schema = %{
        name: {:required, :string},
        age: {:integer, {:gte, 0}}
      }

      invalid_data = %{
        "age" => -5
      }

      assert {:error, %{errors: errors}} = MentorPeri.validate(schema, invalid_data)
      assert length(errors) == 2
      assert Enum.any?(errors, fn %{field: field} -> field == "name" end)
      assert Enum.any?(errors, fn %{field: field} -> field == "age" end)
    end

    test "validates list schemas" do
      schema = {:list, :integer}
      valid_data = [1, 2, 3, 4, 5]

      assert {:ok, ^valid_data} = MentorPeri.validate(schema, valid_data)
    end

    test "validates tuple schemas" do
      schema = {:tuple, [:string, :integer, :boolean]}
      valid_data = {"hello", 42, true}

      assert {:ok, ^valid_data} = MentorPeri.validate(schema, valid_data)
    end

    test "validates primitive schemas" do
      assert {:ok, "hello"} = MentorPeri.validate(:string, "hello")
      assert {:ok, 42} = MentorPeri.validate(:integer, 42)
      assert {:ok, true} = MentorPeri.validate(:boolean, true)
    end
  end

  describe "definition/1" do
    test "returns field definitions for map schemas" do
      schema = %{
        name: {:required, :string},
        age: :integer,
        active: :boolean
      }

      fields = MentorPeri.definition(schema)
      assert {:name, :string} in fields
      assert {:age, :integer} in fields
      assert {:active, :boolean} in fields
    end

    test "returns single field for primitive schemas" do
      assert [{:value, :string}] = MentorPeri.definition(:string)
      assert [{:value, :integer}] = MentorPeri.definition(:integer)
    end

    test "extracts base types from complex schemas" do
      schema = %{
        items: {:list, :string},
        count: {:integer, {:gte, 0}},
        status: {:enum, [:active, :inactive]}
      }

      fields = MentorPeri.definition(schema)
      assert {:items, :list} in fields
      assert {:count, :integer} in fields
      assert {:status, :enum} in fields
    end
  end

  describe "to_json_schema/1" do
    test "converts map schemas to JSON schema" do
      schema = %{
        name: {:required, :string},
        age: {:integer, {:gte, 0}},
        active: :boolean
      }

      json_schema = MentorPeri.to_json_schema(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["age"]["type"] == "integer"
      assert json_schema["properties"]["age"]["minimum"] == 0
      assert json_schema["properties"]["active"]["type"] == "boolean"
      assert json_schema["required"] == ["name"]
    end

    test "converts list schemas to JSON schema" do
      schema = {:list, :string}
      json_schema = MentorPeri.to_json_schema(schema)

      assert json_schema["type"] == "array"
      assert json_schema["items"]["type"] == "string"
    end

    test "converts tuple schemas to JSON schema" do
      schema = {:tuple, [:string, :integer]}
      json_schema = MentorPeri.to_json_schema(schema)

      assert json_schema["type"] == "array"

      assert json_schema["prefixItems"] == [
               %{"type" => "string"},
               %{"type" => "integer"}
             ]

      assert json_schema["minItems"] == 2
      assert json_schema["maxItems"] == 2
    end

    test "converts enum schemas to JSON schema" do
      schema = {:enum, ["active", "inactive", "pending"]}
      json_schema = MentorPeri.to_json_schema(schema)

      assert json_schema["enum"] == ["active", "inactive", "pending"]
    end

    test "converts string constraints to JSON schema" do
      min_schema = {:string, {:min, 5}}
      json = MentorPeri.to_json_schema(min_schema)
      assert json["minLength"] == 5

      max_schema = {:string, {:max, 10}}
      json = MentorPeri.to_json_schema(max_schema)
      assert json["maxLength"] == 10

      regex_schema = {:string, {:regex, ~r/^[A-Z]/}}
      json = MentorPeri.to_json_schema(regex_schema)
      assert json["pattern"] == "^[A-Z]"
    end

    test "converts numeric constraints to JSON schema" do
      gt_schema = {:integer, {:gt, 0}}
      json = MentorPeri.to_json_schema(gt_schema)
      assert json["exclusiveMinimum"] == 0

      lte_schema = {:float, {:lte, 100.0}}
      json = MentorPeri.to_json_schema(lte_schema)
      assert json["maximum"] == 100.0

      range_schema = {:integer, {:range, {1, 10}}}
      json = MentorPeri.to_json_schema(range_schema)
      assert json["minimum"] == 1
      assert json["maximum"] == 10
    end

    test "converts nested object schemas" do
      schema = %{
        user: %{
          name: {:required, :string},
          profile: %{
            age: :integer,
            bio: :string
          }
        }
      }

      json_schema = MentorPeri.to_json_schema(schema)

      assert json_schema["properties"]["user"]["type"] == "object"
      assert json_schema["properties"]["user"]["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["user"]["properties"]["profile"]["type"] == "object"

      assert json_schema["properties"]["user"]["properties"]["profile"]["properties"]["age"][
               "type"
             ] == "integer"
    end
  end

  describe "generate_field_descriptions/1" do
    test "generates descriptions for map schemas" do
      schema = %{
        name: {:required, :string},
        age: {:integer, {:gte, 18}},
        tags: {:list, :string}
      }

      descriptions = MentorPeri.generate_field_descriptions(schema)

      assert descriptions.name == "Required string"
      assert descriptions.age == "Optional integer greater than or equal to 18"
      assert descriptions.tags == "Optional array of string elements"
    end

    test "generates description for non-map schemas" do
      descriptions = MentorPeri.generate_field_descriptions(:string)
      assert descriptions == %{"value" => "Optional string"}

      list_desc = MentorPeri.generate_field_descriptions({:list, :integer})
      assert list_desc == %{"value" => "Optional array of integer elements"}
    end
  end
end
