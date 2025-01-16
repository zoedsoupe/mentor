# Mentor

> ![WARNING]
> This library is under active development and isn't ready for production use, expect breaking changes.

Because we love composability!

No magic, but a higher-level API to generate structed output based on a "schema", it can be:
- a raw map/struct/data structure (string, tuple and so on)
- an `Ecto` schema (embedded, database or schemaless changesets)
- a `peri` schema definition

## Installation

```elixir
def deps do
  [
    {:mentor, "~> 0.1.0"}
  ]
end
```

## Usage

Given a structure that you wanna have a LLM to output, let's say a raw `User` struct:

```elixir
defmodule User do
  @moduledoc """
  
  """

  @derive Mentor.Schema
  defstruct [:name, :age]
end
```

_TODO_

## References
- [OpenAI text generation docs](https://platform.openai.com/docs/guides/text-generation)
- [OpenAI structured outputs docs](https://platform.openai.com/docs/guides/structured-outputs)
- [OpenAI input formatting cookbook](https://cookbook.openai.com/examples/how_to_format_inputs_to_chatgpt_models)
- [Anthropic Message format](https://docs.anthropic.com/en/api/messages#body-messages)

## Spiritual inspirations
- [instructor_ex](https://hexdocs.pm/instructor)
- [instructor_lite](https://hexdocs.pm/instructor_lite)
