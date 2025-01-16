defmodule Mentor.LLM.Adapters.OpenAI do
  @moduledoc false

  use Mentor.LLM.Adapter

  @impl true
  def complete(%Mentor{schema: schema}) do
    struct(schema)
  end

  @impl true
  def validate_config(config) do
  end

  # TODO
  @impl true
  def parse_message_content(content) when is_list(content) do
    Enum.reduce_while(content, [], fn content, acc ->
      case parse_message_content(content) do
        {:ok, inner} -> {:cont, acc ++ [inner]}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> then(fn
      content when is_list(content) -> {:ok, content}
      err -> err
    end)
  end

  def parse_message_content(content) when is_binary(content) do
    {:ok, %{type: "text", text: "content"}}
  end

  def parse_message_content(content) when is_binary(content) do
  end
end
