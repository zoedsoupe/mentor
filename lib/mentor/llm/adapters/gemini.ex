defmodule Mentor.LLM.Adapters.Gemini do
  use Mentor.LLM.Adapter

  # just a helper info to be used in docs
  # as of April 2024, current Gemini models
  @known_models ~w[gemini-2.0-pro gemini-2.0-pro-latest gemini-2.0-pro-vision gemini-2.0-flash gemini-2.0-flash-latest gemini-2.0-flash-vision gemini-1.5-pro gemini-1.5-pro-latest gemini-1.5-flash]

  # Example base64 image used in documentation
  @doc_b64_image "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

  @options NimbleOptions.new!(
             url: [
               type: :string,
               default: "https://generativelanguage.googleapis.com/v1beta/models",
               doc: "Base API endpoint to use for sending requests"
             ],
             api_key: [
               type: :string,
               required: true,
               doc: "Google Generative AI API key"
             ],
             model: [
               type: {:or, [:string, {:in, @known_models}]},
               required: true,
               doc:
                 "The Gemini model to query on, known models are: `#{inspect(@known_models, pretty: true)}`"
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
  An adapter for integrating Google's Gemini language models with the Mentor framework.

  This module implements the `Mentor.LLM.Adapter` behaviour, enabling communication between Mentor and Google Generative AI API. It facilitates sending prompts and receiving responses, ensuring compatibility with Mentor's expected data structures.

  ## Options

  #{NimbleOptions.docs(@options)}

  ## Usage

  To utilize this adapter, configure your `Mentor` instance with the appropriate options:

      config = [
        api_key: System.get_env("GEMINI_API_KEY"),
        model: "gemini-2.0-pro"
      ]

      mentor = Mentor.start_chat_with!(Mentor.LLM.Adapters.Gemini, adapter_config: config)

  ## Multimodal Support

  The adapter supports multimodal inputs like images. You can use various image format input styles:

  ### Using Base64 Data URLs (OpenAI style):

      # Using the sample base64 image (1x1 transparent pixel)
      b64_encoded_image = @doc_b64_image

      Mentor.append_message(%{
        role: "user",
        content: [
          %{
            type: "image_url",
            image_url: %{
              url: "data:image/jpeg;base64,#{@doc_b64_image}"
            }
          }
        ]
      })

  ### Using a Direct URL:

      Mentor.append_message(%{
        role: "user",
        content: [
          %{
            type: "image_url",
            image_url: %{
              url: "https://example.com/image.jpg"
            }
          }
        ]
      })

  ### Gemini Direct Format:

      Mentor.append_message(%{
        role: "user",
        content: [
          %{
            type: "image_base64",
            data: "base64_encoded_data",
            mime_type: "image/jpeg"
          }
        ]
      })

  ## Considerations

  - **API Key Security**: Ensure your Google API key is stored securely and not exposed in your codebase.
  - **Model Availability**: Verify that the specified model is available and suitable for your use case. Refer to Google's official documentation for the most up-to-date list of models and their capabilities.
  - **Vision Models**: For image processing, use vision-capable models like `gemini-2.0-pro-vision` or `gemini-2.0-flash-vision`.
  - **Error Handling**: The `complete/1` function returns `{:ok, response}` on success or `{:error, reason}` on failure. Implement appropriate error handling in your application to manage these scenarios.

  By adhering to the `Mentor.LLM.Adapter` behaviour, this module ensures seamless integration with Google's Gemini API, allowing for efficient and effective language model interactions within the Mentor framework.
  """

  @keys Keyword.keys(@options.schema)

  @impl true
  def complete(%Mentor{config: config} = mentor) do
    config = Keyword.take(config, @keys)

    with {:ok, config} <- NimbleOptions.validate(config, @options),
         {:ok, resp} <- make_gemini_request(mentor, config) do
      if resp.status == 200 do
        JSON.decode!(resp.body)
        |> parse_response_body(mentor.__schema__)
      else
        {:error, resp}
      end
    end
  end

  defp make_gemini_request(%Mentor{} = mentor, config) do
    body = make_gemini_body(mentor, config)
    model = config[:model]
    url = "#{config[:url]}/#{model}:generateContent?key=#{config[:api_key]}"

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    mentor.http_client.request(url, body, headers, config[:http_options])
  end

  defp make_gemini_body(%Mentor{} = mentor, config) do
    # Special handling for Gemini's message formatting
    contents = prepare_gemini_contents(mentor.messages)
    schema_without_additional_props = Map.delete(mentor.json_schema, :additionalProperties)

    %{
      contents: contents,
      generationConfig: %{
        temperature: config[:temperature],
        response_mime_type: "application/json",
        response_schema: schema_without_additional_props
      }
    }
  end

  # Special handling for Gemini message formatting
  defp prepare_gemini_contents(messages) do
    # Find system message if it exists
    system_message = Enum.find(messages, fn msg -> msg.role == "system" end)
    # Extract non-system messages
    user_messages = Enum.reject(messages, fn msg -> msg.role == "system" end)

    case {system_message, user_messages} do
      # Both system and user message exist
      {%{content: system_content}, [%{role: "user", content: user_content} | rest]} ->
        # Create a single message with all content from system and first user message
        parts = create_combined_parts(system_content, user_content)

        # Return as a single user message followed by any remaining messages
        [%{role: "user", parts: parts}] ++
          Enum.map(rest, fn message ->
            %{
              role: convert_role(message.role),
              parts: convert_message_content(message.content)
            }
          end)

      # No system message, just process user messages normally
      {nil, user_msgs} ->
        Enum.map(user_msgs, fn message ->
          %{
            role: convert_role(message.role),
            parts: convert_message_content(message.content)
          }
        end)

      # System message exists but no user messages
      {%{content: system_content}, []} ->
        [%{role: "user", parts: [%{text: system_content}]}]
    end
  end

  # Create combined parts array with system content at beginning
  defp create_combined_parts(system_content, user_content) do
    system_part = %{text: system_content}

    # Add system content as first text part, then all user content parts
    user_parts =
      if is_list(user_content) do
        # User content is already a list of parts (multimodal)
        convert_message_content(user_content)
      else
        # User content is just text
        [%{text: user_content}]
      end

    # Check if the first user part is text that we can merge with system content
    case user_parts do
      [%{text: text} | rest] ->
        # Merge first text part with system content
        [%{text: "#{system_content}\n\n#{text}"}] ++ rest

      # Non-text first part, just add system content as first part
      _ ->
        [system_part] ++ user_parts
    end
  end

  # Handle text-only content
  defp convert_message_content(content) when is_binary(content) do
    [%{text: content}]
  end

  # Handle array of content parts (for multimodal)
  defp convert_message_content(content) when is_list(content) do
    Enum.map(content, fn
      # Text content
      %{type: "text", text: text} ->
        %{text: text}

      # Plain text without type
      text when is_binary(text) ->
        %{text: text}

      # Image content (OpenAI format)
      %{type: "image_url", image_url: %{url: url} = image_url} ->
        handle_image_url(url, image_url)

      # Handle image parts directly (Gemini native format)
      %{type: "image", image: %{} = image} ->
        image

      # Handle base64 encoded images
      %{type: "image_base64", data: data, mime_type: mime_type} ->
        %{inline_data: %{data: data, mime_type: mime_type}}

      # Fallback for other content types
      other ->
        %{text: "Unsupported content type: #{inspect(other)}"}
    end)
  end

  # Handle individual image from different sources
  defp handle_image_url("data:" <> rest = _url, _image_url) do
    # Handle base64 data URLs
    case String.split(rest, ";base64,", parts: 2) do
      [mime_type, base64_data] ->
        %{inline_data: %{data: base64_data, mime_type: mime_type}}

      _ ->
        %{text: "Invalid base64 image data"}
    end
  end

  # Handle HTTP URLs
  defp handle_image_url("http://" <> _rest = url, _image_url) do
    %{file_data: %{file_uri: url, mime_type: guess_mime_type(url)}}
  end

  # Handle HTTPS URLs
  defp handle_image_url("https://" <> _rest = url, _image_url) do
    %{file_data: %{file_uri: url, mime_type: guess_mime_type(url)}}
  end

  # Fallback for other URL formats
  defp handle_image_url(_url, _image_url) do
    %{text: "Unsupported image URL format"}
  end

  # Simple MIME type guesser based on file extension
  defp guess_mime_type(url) do
    case Path.extname(url) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      # Default assumption
      _ -> "image/jpeg"
    end
  end

  # Convert OpenAI roles to Gemini roles
  defp convert_role("user"), do: "user"
  defp convert_role("assistant"), do: "model"
  # Gemini doesn't have system role, using user instead
  defp convert_role("system"), do: "user"

  # Parse Gemini response body and extract JSON content
  defp parse_response_body(
         %{"candidates" => [%{"content" => %{"parts" => [%{"text" => content} | _]}} | _]},
         _schema
       ) do
    # Simply parse the JSON content directly
    case JSON.decode(content) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:error, _} ->
        # If direct parsing fails, try to extract a JSON object from the text
        case Regex.run(~r/\{.+\}/s, content) do
          [json] ->
            case JSON.decode(json) do
              {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
              {:error, reason} -> {:error, "Failed to parse extracted JSON: #{reason}"}
            end

          _ ->
            {:error, "Failed to extract JSON from Gemini response"}
        end
    end
  end

  defp parse_response_body(response, _schema) do
    # Fallback for unexpected response structure
    {:error, "Invalid response format from Gemini API: #{inspect(response)}"}
  end
end
