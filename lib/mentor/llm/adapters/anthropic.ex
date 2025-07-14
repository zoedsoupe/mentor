defmodule Mentor.LLM.Adapters.Anthropic do
  use Mentor.LLM.Adapter

  @default_url "https://api.anthropic.com/v1/messages"
  @default_max_tokens 4096
  @default_anthropic_version "2023-06-01"

  @known_models [
    "claude-3-5-sonnet-20241022",
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307"
  ]

  @base_system_prompt """
  You should always return only the structured output as JSON, no additional data or content should be returned,
  respecting always the input schema and field description gave to you.


  """

  @options NimbleOptions.new!(
             api_key: [
               type: :string,
               required: true,
               doc: "Your Anthropic API key"
             ],
             model: [
               type: {:or, [:string, {:in, @known_models}]},
               required: true,
               doc: "The Claude model to use"
             ],
             temperature: [
               type: :float,
               default: 1.0,
               doc: "Sampling temperature between 0 and 1"
             ],
             max_tokens: [
               type: :pos_integer,
               default: @default_max_tokens,
               doc: "Maximum number of tokens to generate"
             ],
             url: [
               type: :string,
               default: @default_url,
               doc: "API endpoint URL"
             ],
             anthropic_version: [
               type: :string,
               default: @default_anthropic_version,
               doc: "Anthropic API version"
             ],
             http_options: [
               type: :keyword_list,
               default: [],
               doc: "Additional options for the HTTP client"
             ]
           )

  @moduledoc """
  Anthropic adapter for Mentor.

  This adapter provides integration with Anthropic's Claude models through their Messages API.

  ## Configuration

  #{NimbleOptions.docs(@options)}

  ## Example

      Mentor.start_chat_with!(@person_schema)
      |> Mentor.configure_adapter({Mentor.LLM.Adapters.Anthropic, api_key: "your-key", model: "claude-3-5-sonnet-20241022"})
      |> Mentor.append_message(:user, "Generate a person with the name John")
      |> Mentor.complete()
  """

  @impl Mentor.LLM.Adapter
  def complete(%Mentor{} = mentor) do
    with {:ok, config} <- NimbleOptions.validate(mentor.config, @options),
         {:ok, response} <- make_request(config, mentor) do
      parse_response(response)
    end
  end

  defp format_message(%{role: role, content: content}) do
    %{
      role: to_string(role),
      content: format_content(content)
    }
  end

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content),
    do: Enum.map(content, &format_content_part/1)

  defp format_content_part(%{type: "text", text: text}), do: %{type: "text", text: text}

  defp format_content_part(%{type: "image_base64", data: data, mime_type: mime_type}) do
    %{
      type: "image",
      source: %{
        type: "base64",
        media_type: mime_type,
        data: data
      }
    }
  end

  defp format_content_part(part), do: part

  defp maybe_append_custom_system_prompt(body, messages) do
    {system_messages, regular_messages} =
      Enum.split_with(messages, fn msg -> msg.role == "system" end)

    case system_messages do
      [] ->
        {Map.put(body, :system, @base_system_prompt), regular_messages}

      msgs ->
        system_prompt = Enum.map_join(msgs, "\n\n", fn msg -> msg.content end)
        {Map.put(body, :system, @base_system_prompt <> system_prompt), regular_messages}
    end
  end

  defp make_request(config, mentor) do
    {body, regular_messages} = maybe_append_custom_system_prompt(%{}, mentor.messages)

    json_schema_message = """

    You should respect the following schema: #{inspect(mentor.json_schema, pretty: true)}
    """

    body =
      Map.merge(body, %{
        model: config[:model],
        messages: Enum.map(regular_messages, &format_message/1),
        max_tokens: config[:max_tokens],
        temperature: config[:temperature],
        system: body.system <> json_schema_message
      })

    headers = [
      {"x-api-key", config[:api_key]},
      {"anthropic-version", config[:anthropic_version]},
      {"content-type", "application/json"}
    ]

    case mentor.http_client.request(config[:url], body, headers, config[:http_options]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        error_message = parse_error_body(body, status)
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp parse_error_body(body, status) do
    case JSON.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        "Anthropic API error (#{status}): #{message}"

      {:ok, %{"error" => error}} ->
        "Anthropic API error (#{status}): #{error}"

      _ ->
        "Anthropic API error (#{status}): #{body}"
    end
  end

  defp parse_response(body) do
    with {:ok, decoded} <- JSON.decode(body),
         {:ok, content} <- extract_content(decoded) do
      JSON.decode(content)
    else
      {:error, reason} ->
        {:error, "Failed to parse response: #{inspect(reason)}"}
    end
  end

  defp extract_content(%{"content" => [%{"text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_content(%{"content" => []}) do
    {:ok, "{}"}
  end

  defp extract_content(%{"content" => content}) do
    {:error, "Unexpected content format: #{inspect(content)}"}
  end

  defp extract_content(response) do
    {:error, "No content found in response: #{inspect(response)}"}
  end
end
