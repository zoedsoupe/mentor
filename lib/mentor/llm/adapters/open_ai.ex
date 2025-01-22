defmodule Mentor.LLM.Adapters.OpenAI do
  use Mentor.LLM.Adapter

  # just a helper info to be used in docs, since user can pass any string as value
  # 2025-01-17 at https://platform.openai.com/docs/models#current-model-aliases
  @known_models ~w[gpt-4o gpt-4o-mini o1 o1-mini o1-preview chatgpt-4o-latest gpt-4o-realtime-preview gpt-4o-mini-realtime-preview gpt-4o-audio-preview]

  @options NimbleOptions.new!(
             url: [
               type: :string,
               default: "https://api.openai.com/v1/chat/completions",
               doc: "API endpoint to use for sending requests"
             ],
             api_key: [
               type: :string,
               required: true,
               doc: "OpenAI API key"
             ],
             model: [
               type: {:or, [:string, {:in, @known_models}]},
               required: true,
               doc:
                 "The OpenAI model to query on, known models are: `#{inspect(@known_models, pretty: true)}`"
             ],
             temperature: [
               type: :float,
               default: 1.0,
               doc:
                 "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic."
             ]
           )

  @moduledoc """
  An adapter for integrating OpenAI's language models with the Mentor framework.

  This module implements the `Mentor.LLM.Adapter` behaviour, enabling communication between Mentor and OpenAI's API. It facilitates sending prompts and receiving responses, ensuring compatibility with Mentor's expected data structures.

  ## Options

  #{NimbleOptions.docs(@options)}

  ## Usage

  To utilize this adapter, configure your `Mentor` instance with the appropriate options:

      config = [
        url: "https://api.openai.com/v1/chat/completions",
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-4o"
      ]

      mentor = Mentor.start_chat_with!(Mentor.LLM.Adapters.OpenAI, adapter_config: config)

  ## Considerations

  - **API Key Security**: Ensure your OpenAI API key is stored securely and not exposed in your codebase.
  - **Model Availability**: Verify that the specified model is available and suitable for your use case. Refer to OpenAI's official documentation for the most up-to-date list of models and their capabilities.
  - **Error Handling**: The `complete/1` function returns `{:ok, response}` on success or `{:error, reason}` on failure. Implement appropriate error handling in your application to manage these scenarios.

  By adhering to the `Mentor.LLM.Adapter` behaviour, this module ensures seamless integration with OpenAI's API, allowing for efficient and effective language model interactions within the Mentor framework.
  """

  @keys Keyword.keys(@options.schema)

  @impl true
  def complete(%Mentor{config: config} = mentor) do
    config = Keyword.take(config, @keys)

    with {:ok, config} <- NimbleOptions.validate(config, @options),
         {:ok, resp} <- make_open_ai_request(mentor, config) do
      if resp.status == 200 do
        JSON.decode!(resp.body)
        |> parse_response_body()
      else
        {:error, resp}
      end
    end
  end

  defp make_open_ai_request(%Mentor{} = mentor, config) do
    body = make_open_ai_body(mentor, config)

    headers = [
      {"content-type", "application/json"},
      {"accept", "aplication/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]

    mentor.http_client.request(config[:url], body, headers,
      receive_timeout: 60_000,
      request_timeout: 20_000,
      pool_timeout: 70_000
    )
  end

  defp make_open_ai_body(%Mentor{} = mentor, config) do
    %{
      messages: mentor.messages,
      model: config[:model],
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "schema",
          strict: true,
          schema: mentor.json_schema
        }
      }
    }
  end

  defp parse_response_body(%{"choices" => [message]}) do
    content = get_in(message, ["message", "content"])
    {:ok, if(content, do: JSON.decode!(content), else: %{})}
  end
end
