defmodule Mentor.Completion do
  @moduledoc """
  Handles interaction with LLMs for structured responses with multiple messages.
  """

  alias Mentor.Ecto.Schema

  @retry_limit 3

  def generate(schema, _messages) do
    Enum.reduce_while(1..@retry_limit, {:error, :validation_failed}, fn _, _ ->
      with {:ok, response} <- nil,
           {:ok, data} <- Schema.validate(schema, response) do
        {:halt, {:ok, data}}
      else
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
