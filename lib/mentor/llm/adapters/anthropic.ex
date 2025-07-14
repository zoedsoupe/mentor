defmodule Mentor.LLM.Adapters.Anthropic do
  @moduledoc """
  Anthropic adapter for Mentor.

  This adapter provides integration with Anthropic's Claude models through their Messages API.

  ## Configuration

  The adapter accepts the following configuration options:

    * `:api_key` - Required. Your Anthropic API key.
    * `:model` - Required. The Claude model to use (e.g., "claude-3-5-sonnet-20241022").
    * `:temperature` - Optional. Sampling temperature between 0 and 1. Defaults to 1.0.
    * `:max_tokens` - Optional. Maximum number of tokens to generate. Defaults to 4096.
    * `:url` - Optional. API endpoint URL. Defaults to "https://api.anthropic.com/v1/messages".
    * `:anthropic_version` - Optional. API version. Defaults to "2023-06-01".
    * `:http_options` - Optional. Additional options for the HTTP client.

  ## Example

      Mentor.start_chat_with!(@person_schema)
      |> Mentor.configure_adapter({Mentor.LLM.Adapters.Anthropic, api_key: "your-key", model: "claude-3-5-sonnet-20241022"})
      |> Mentor.append_message(:user, "Generate a person with the name John")
      |> Mentor.complete()
  """

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

  @options [
    api_key: [
      type: :string,
      required: true,
      doc: "Your Anthropic API key"
    ],
    model: [
      type: {:in, @known_models},
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
  ]

  @impl Mentor.LLM.Adapter
  def complete(%Mentor{} = mentor) do
    with {:ok, config} <- validate_config(mentor.config),
         {:ok, messages} <- prepare_messages(mentor),
         request <- build_request(messages, config),
         {:ok, response} <- make_request(request, config, mentor),
         {:ok, parsed} <- parse_response(response) do
      {:ok, parsed}
    end
  end

  defp validate_config(config) do
    case NimbleOptions.validate(config, @options) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, Exception.message(error)}
    end
  end

  defp prepare_messages(mentor) do
    {:ok, mentor.messages}
  end

  defp format_messages_for_anthropic(messages) do
    messages
    |> Enum.map(&format_message/1)
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

  defp build_request(messages, config) do
    # Extract system messages from the messages list
    {system_messages, regular_messages} =
      Enum.split_with(messages, fn msg -> msg.role == "system" end)

    # Combine all system messages into one
    system_prompt =
      case system_messages do
        [] ->
          nil

        msgs ->
          msgs
          |> Enum.map(fn msg -> msg.content end)
          |> Enum.join("\n\n")
      end

    body = %{
      model: config[:model],
      messages: format_messages_for_anthropic(regular_messages),
      max_tokens: config[:max_tokens],
      temperature: config[:temperature]
    }

    body = if system_prompt, do: Map.put(body, :system, system_prompt), else: body

    headers = [
      {"x-api-key", config[:api_key]},
      {"anthropic-version", config[:anthropic_version]},
      {"content-type", "application/json"}
    ]

    %{
      url: config[:url],
      headers: headers,
      body: body,
      options: config[:http_options]
    }
  end

  defp make_request(request, _config, mentor) do
    http_client = mentor.http_client || Mentor.HTTPClient.Default

    case http_client.request(request.url, request.body, request.headers, request.options) do
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
        "Anthropic API error (#{status}): #{inspect(error)}"

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

  defp extract_content(%{"content" => content}) do
    {:error, "Unexpected content format: #{inspect(content)}"}
  end

  defp extract_content(response) do
    {:error, "No content found in response: #{inspect(response)}"}
  end
end
