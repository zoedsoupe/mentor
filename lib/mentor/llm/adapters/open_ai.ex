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
             ],
             http_options: [
               type: :keyword_list,
               default: [],
               keys: [
                 pool_timeout: [type: :integer],
                 receive_timeout: [type: :integer],
                 request_timeout: [type: :integer]
               ]
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

    mentor.http_client.request(config[:url], body, headers, config[:http_options])
  end

  defp make_open_ai_body(%Mentor{} = mentor, config) do
    json_schema = wrap_schema_if_needed(mentor.json_schema)

    %{
      messages: mentor.messages,
      model: config[:model],
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "schema",
          strict: true,
          schema: json_schema
        }
      }
    }
  end

  defp wrap_schema_if_needed(%{"type" => "object"} = schema) do
    ensure_required_array(schema)
  end

  defp wrap_schema_if_needed(schema) do
    %{
      "type" => "object",
      "properties" => %{"value" => schema},
      "required" => ["value"],
      "additionalProperties" => false
    }
  end

  defp ensure_required_array(%{"properties" => properties} = schema) when is_map(properties) do
    all_keys = Map.keys(properties)

    schema
    |> Map.put("required", all_keys)
    |> Map.update("properties", %{}, fn props ->
      Map.new(props, fn {key, value} ->
        {key, ensure_nested_required(value)}
      end)
    end)
    |> ensure_additional_properties()
  end

  defp ensure_required_array(schema), do: schema

  defp ensure_nested_required(%{"type" => "object"} = schema) do
    ensure_required_array(schema)
  end

  defp ensure_nested_required(%{"oneOf" => _}) do
    %{
      "type" => "object",
      "additionalProperties" => false
    }
  end

  defp ensure_nested_required(%{"type" => "array"} = schema) do
    if Map.has_key?(schema, "items") do
      schema
    else
      Map.put(schema, "items", %{"type" => "string"})
    end
  end

  defp ensure_nested_required(schema), do: schema

  defp ensure_additional_properties(schema) do
    if Map.get(schema, "type") == "object" and not Map.has_key?(schema, "additionalProperties") do
      Map.put(schema, "additionalProperties", false)
    else
      schema
    end
  end

  defp parse_response_body(%{"choices" => [message]}) do
    content = get_in(message, ["message", "content"])

    if content do
      decoded = JSON.decode!(content)

      result =
        case decoded do
          %{"value" => value} when map_size(decoded) == 1 -> value
          other -> other
        end

      {:ok, result}
    else
      {:ok, %{}}
    end
  end
end
