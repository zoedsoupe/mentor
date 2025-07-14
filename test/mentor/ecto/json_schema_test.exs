defmodule Mentor.Ecto.JSONSchemaTest do
  use ExUnit.Case, async: true

  alias Mentor.Ecto.JSONSchema

  defmodule BasicSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
      field :age, :integer
      field :description, :string, default: ""
      field :active, :boolean, default: true
    end
  end

  defmodule Metadata do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :version, :string
      field :tags, {:array, :string}, default: []
    end
  end

  defmodule SchemaWithEmbedded do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :title, :string
      field :context, :map, default: %{}
      embeds_one :metadata, Metadata
    end
  end

  defmodule NestedSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :integer
      field :data, :string
    end
  end

  defmodule SchemaWithAssociation do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
      embeds_many :items, NestedSchema
    end
  end

  describe "from_ecto_schema/1" do
    test "generates basic JSON schema with required fields" do
      result = JSONSchema.from_ecto_schema(BasicSchema)

      assert result == %{
               title: "BasicSchema",
               type: "object",
               properties: %{
                 name: %{type: "string"},
                 age: %{type: "integer"},
                 description: %{type: "string"},
                 active: %{type: "boolean"}
               },
               required: ["age", "name"],
               additionalProperties: false
             }
    end

    test "fields with defaults are not included in required array" do
      result = JSONSchema.from_ecto_schema(BasicSchema)

      # Fields without defaults should be required
      assert "name" in result.required
      assert "age" in result.required

      # Fields with defaults should NOT be required
      refute "description" in result.required
      refute "active" in result.required
    end

    test "handles embedded schemas with defaults" do
      result = JSONSchema.from_ecto_schema(SchemaWithEmbedded)

      assert result == %{
               title: "SchemaWithEmbedded",
               type: "object",
               properties: %{
                 title: %{type: "string"},
                 context: %{type: "object", additionalProperties: %{type: "string"}},
                 metadata: %{"$ref": "#/$defs/Metadata"}
               },
               required: ["metadata", "title"],
               additionalProperties: false,
               "$defs": %{
                 "Metadata" => %{
                   title: "Metadata",
                   type: "object",
                   properties: %{
                     version: %{type: "string"},
                     tags: %{type: "array", items: %{type: "string"}}
                   },
                   required: ["version"],
                   additionalProperties: false
                 }
               }
             }
    end

    test "handles embeds_many relationships" do
      result = JSONSchema.from_ecto_schema(SchemaWithAssociation)

      assert result == %{
               title: "SchemaWithAssociation",
               type: "object",
               properties: %{
                 name: %{type: "string"},
                 items: %{
                   type: "array",
                   items: %{"$ref": "#/$defs/NestedSchema"}
                 }
               },
               required: ["name"],
               additionalProperties: false,
               "$defs": %{
                 "NestedSchema" => %{
                   title: "NestedSchema",
                   type: "object",
                   properties: %{
                     id: %{type: "integer"},
                     data: %{type: "string"}
                   },
                   required: ["data", "id"],
                   additionalProperties: false
                 }
               }
             }
    end

    test "handles inline ecto types map" do
      ecto_types = %{
        name: :string,
        count: :integer,
        active: :boolean
      }

      result = JSONSchema.from_ecto_schema(ecto_types)

      assert result == %{
               title: "root",
               type: "object",
               properties: %{
                 name: %{type: "string"},
                 count: %{type: "integer"},
                 active: %{type: "boolean"}
               },
               required: ["active", "count", "name"],
               additionalProperties: false
             }
    end
  end
end
