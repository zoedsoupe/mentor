# Mentor

> [!WARNING]
> This library is under actively development, expect breaking changes, although the main public API is kinda stable

[![mentor version](https://img.shields.io/hexpm/v/mentor.svg)](https://hex.pm/packages/mentor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/mentor)
[![Hex Downloads](https://img.shields.io/hexpm/dt/mentor)](https://hex.pm/packages/mentor)

Because we love composability!

No magic, but a higher-level API to generate structured output with LLM, based on a "schema", it can be:
- **Ecto schemas** - Database-backed schemas, embedded schemas, and schemaless changesets with full validation support
- **Peri schemas** - Flexible runtime schemas supporting:
  - Maps with field validation and constraints
  - Lists with item type validation
  - Tuples with fixed element types
  - Enums for restricted value sets
  - Primitive types (string, integer, float, boolean, etc.)
  - Complex nested structures
  - Custom validation rules

## Installation

```elixir
def deps do
  [
    {:mentor, "~> 0.2"}
  ]
end
```

## Usage

The `mentor` library is useful for coaxing an LLM to return JSON that maps to a schema that you provide, rather than the default unstructured text output. If you define your own validation logic, `mentor` can automatically retry prompts when validation fails (returning natural language error messages to the LLM, to guide it when making corrections).

`mentor` is designed to be used with a variaty of LLM providers like [OpenAI API](https://platform.openai.com/docs/api-reference/chat-completions/create), [llama.cpp](https://github.com/ggerganov/llama.cpp), [Bumblebee](https://github.com/elixir-nx/bumblebee) and so on (check the [LLM.Adapters](#llm-adapters) section) by using an extendable adapter behavior.

At its simplest, usage with `Ecto` is pretty straightforward:

1. Create an `Ecto` schema, with a native `@moduledoc` string that explains the schema definition to the LLM or define a `llm_description/0` callback to return it.
2. Use the `Mentor.Ecto.Schema` macro to validate and fetch the documentation prompt and enforce callbacks.
3. Define an usual `changeset/2` function on the schema.
4. Construct a `Mentor` and pass it to `Mentor.complete/1` to generate the structured output.

```elixir
defmodule SpamPrediction do
  @moduledoc """
  ## Field Descriptions:
  - class: Whether or not the email is spam.
  - reason: A short, less than 10 word rationalization for the classification.
  - score: A confidence score between 0.0 and 1.0 for the classification.
  """

  use Ecto.Schema
  use Mentor.Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :class, Ecto.Enum, values: [:spam, :not_spam]
    field :reason, :string
    field :score, :float
  end

  @impl true
  def changeset(%__MODULE__{} = source, %{} = attrs) do
    source
    |> cast(attrs, [:class, :reason, :score])
    |> validate_number(:score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  # this can be in another module and the function name doesn't matter
  def instruct(text) when is_binary(text) do
    Mentor.start_chat_with!(Mentor.LLM.Adapters.OpenAI,
      schema: __MODULE__,
      max_retries: 2 # defaults to 3
    )
    # append how many custom messages you want
    |> Mentor.append_message(%{
      role: "user",
      content: "Classify the following email: #{text}"
    })
    # pass specific config to the adapter
    |> Mentor.configure_adapter(api_key: System.fetch_env!("OPENAI_API_KEY"), model: "gpt-4o-mini")
    # you can also overwrite the initial prompt
    |> Mentor.overwrite_initial_prompt("""
    Your purpose is to classify customer support emails as either spam or not.
    This is for a clothing retail business.
    They sell all types of clothing.
    """)
    # trigger the instruction to be completed (aka sent it to the LLM)
    # since all above steps are lazy
    |> Mentor.complete()
  end
end

SpamPrediction.instruct("""
Hello I am a Nigerian prince and I would like to send you money
""")
# => {:ok, %SpamPrediction{class: :spam, reason: "Nigerian prince email scam", score: 0.98}}
```

### Using Peri Schemas

Peri schemas provide a flexible way to define structured output without the overhead of Ecto schemas:

```elixir
# Define a Peri schema for product information
product_schema = %{
  name: {:required, :string},
  price: {:required, {:float, {:gt, 0}}},
  currency: {:required, {:enum, ["USD", "EUR", "GBP"]}},
  in_stock: :boolean,
  tags: {:list, :string}
}

mentor = Mentor.start_chat_with!(
  Mentor.LLM.Adapters.OpenAI,
  schema: product_schema
)
|> Mentor.configure_adapter(
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  model: "gpt-4o-mini"
)
|> Mentor.append_message(%{
  role: "user",
  content: "Generate product info for a premium mechanical keyboard"
})
|> Mentor.complete()

# => {:ok, %{
#      name: "Premium Mechanical Keyboard",
#      price: 199.99,
#      currency: "USD",
#      in_stock: true,
#      tags: ["mechanical", "gaming", "RGB"]
#    }}
```

Peri schemas support various types and constraints:
- Basic types: `:string`, `:integer`, `:float`, `:boolean`, `:atom`
- Date/time types: `:date`, `:time`, `:datetime`, `:naive_datetime`
- Collections: `{:list, type}`, `{:map, value_type}`, `{:tuple, [types]}`
- Constraints: `{:required, type}`, `{:enum, values}`, numeric ranges, string patterns
- Nested objects: Define schemas within schemas for complex structures

> [!NOTE]
> When using OpenAI's adapter, some schema types are automatically wrapped to comply with their structured output requirements:
> - Non-object root schemas are wrapped in an object with a "value" field
> - Array and enum schemas at the root level need this wrapper
> - The adapter handles unwrapping automatically in the response

Check out our [Quickstart Guide](https://hexdocs.pm/mentor/quickstart.html) for more code snippets that you can run locally (in Livebook). Or, to get a better idea of the thinking behind Instructor, read more about our [Philosophy & Motivations](https://hexdocs.pm/mentor/philosophy.html).

## References
- [OpenAI text generation docs](https://platform.openai.com/docs/guides/text-generation)
- [OpenAI structured outputs docs](https://platform.openai.com/docs/guides/structured-outputs)
- [OpenAI input formatting cookbook](https://cookbook.openai.com/examples/how_to_format_inputs_to_chatgpt_models)
- [Anthropic Message format](https://docs.anthropic.com/en/api/messages#body-messages)
- [Google Gemini structured outputs docs](https://ai.google.dev/gemini-api/docs/structured-output?lang=rest)

## Spiritual inspirations
- [instructor_ex](https://hexdocs.pm/instructor)
- [instructor_lite](https://hexdocs.pm/instructor_lite)
