defmodule Mentor.LLM.Adapters.AnthropicTest do
  use ExUnit.Case, async: true

  import Mox

  alias Mentor.LLM.Adapters.Anthropic

  @mock TestHTTPClient

  setup :verify_on_exit!

  defmodule TestSchema do
    @moduledoc """
    A test person schema

    ## Fields
    - `name`: The person's name
    - `age`: The person's age in years
    """
    use Ecto.Schema
    use Mentor.Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
      field :age, :integer
    end

    @impl true
    def changeset(source, params) do
      source
      |> cast(params, [:name, :age])
      |> validate_required([:name, :age])
    end
  end

  describe "complete/1" do
    setup do
      # Simulate what Mentor.complete/1 does
      base_mentor =
        Mentor.start_chat_with!(Anthropic, schema: TestSchema)
        |> Mentor.configure_adapter(
          api_key: "test_key",
          model: "claude-3-5-sonnet-20241022",
          temperature: 0.7,
          max_tokens: 1000
        )
        |> Mentor.configure_http_client(@mock)
        |> Mentor.append_message(%{role: "user", content: "Create a person named John who is 30"})

      # Add system prompt and prepare json_schema like Mentor.complete/1 does
      mandatory = %{role: "system", content: base_mentor.initial_prompt}
      messages = [mandatory | Enum.reverse(base_mentor.messages)]
      json_schema = Mentor.Ecto.JSONSchema.from_ecto_schema(TestSchema)

      mentor = %{base_mentor | messages: messages, json_schema: json_schema}

      {:ok, mentor: mentor}
    end

    test "successfully completes a request", %{mentor: mentor} do
      expect(@mock, :request, fn "https://api.anthropic.com/v1/messages", body, headers, [] ->
        assert {"x-api-key", "test_key"} in headers
        assert {"anthropic-version", "2023-06-01"} in headers
        assert {"content-type", "application/json"} in headers

        # Body is JSON encoded by the HTTP client
        {:ok, decoded_body} = JSON.decode(body)
        assert decoded_body["model"] == "claude-3-5-sonnet-20241022"
        assert decoded_body["temperature"] == 0.7
        assert decoded_body["max_tokens"] == 1000
        assert decoded_body["system"] =~ "You are a highly intelligent"
        assert decoded_body["system"] =~ "A test person schema"
        assert [%{"role" => "user", "content" => content}] = decoded_body["messages"]
        assert content == "Create a person named John who is 30"

        response = %{
          "content" => [
            %{
              "text" => JSON.encode!(%{"name" => "John", "age" => 30})
            }
          ]
        }

        {:ok, %{status: 200, body: JSON.encode!(response)}}
      end)

      assert {:ok, %{"name" => "John", "age" => 30}} = Anthropic.complete(mentor)
    end

    test "handles API errors gracefully", %{mentor: mentor} do
      expect(@mock, :request, fn _, _, _, _ ->
        error_response = %{
          "error" => %{
            "message" => "Invalid API key"
          }
        }

        {:ok, %{status: 401, body: JSON.encode!(error_response)}}
      end)

      assert {:error, "Anthropic API error (401): Invalid API key"} = Anthropic.complete(mentor)
    end

    test "handles network errors", %{mentor: mentor} do
      expect(@mock, :request, fn _, _, _, _ ->
        {:error, :timeout}
      end)

      assert {:error, "HTTP request failed: :timeout"} = Anthropic.complete(mentor)
    end

    test "handles malformed responses", %{mentor: mentor} do
      expect(@mock, :request, fn _, _, _, _ ->
        {:ok, %{status: 200, body: "not json"}}
      end)

      assert {:error, "Failed to parse response: " <> _} = Anthropic.complete(mentor)
    end

    test "supports multimodal content", %{mentor: mentor} do
      mentor =
        mentor
        |> Mentor.append_message(%{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{
              type: "image_base64",
              data: "base64_encoded_image_data",
              mime_type: "image/jpeg"
            }
          ]
        })

      expect(@mock, :request, fn _, body, _, _ ->
        {:ok, decoded_body} = JSON.decode(body)
        [first_msg, second_msg] = decoded_body["messages"]

        assert first_msg["role"] == "user"
        assert first_msg["content"] == "Create a person named John who is 30"

        assert second_msg["role"] == "user"
        assert [text_part, image_part] = second_msg["content"]
        assert text_part == %{"type" => "text", "text" => "What's in this image?"}

        assert image_part == %{
                 "type" => "image",
                 "source" => %{
                   "type" => "base64",
                   "media_type" => "image/jpeg",
                   "data" => "base64_encoded_image_data"
                 }
               }

        response = %{
          "content" => [
            %{
              "text" => JSON.encode!(%{"name" => "Jane", "age" => 25})
            }
          ]
        }

        {:ok, %{status: 200, body: JSON.encode!(response)}}
      end)

      assert {:ok, %{"name" => "Jane", "age" => 25}} = Anthropic.complete(mentor)
    end

    test "uses custom URL when provided", %{mentor: mentor} do
      custom_url = "https://custom.anthropic.api/v1/messages"

      mentor =
        mentor
        |> Mentor.configure_adapter(url: custom_url)

      expect(@mock, :request, fn ^custom_url, _, _, _ ->
        response = %{
          "content" => [
            %{
              "text" => JSON.encode!(%{"name" => "Alice", "age" => 28})
            }
          ]
        }

        {:ok, %{status: 200, body: JSON.encode!(response)}}
      end)

      assert {:ok, %{"name" => "Alice", "age" => 28}} = Anthropic.complete(mentor)
    end

    test "uses custom anthropic version when provided", %{mentor: mentor} do
      mentor =
        mentor
        |> Mentor.configure_adapter(anthropic_version: "2024-01-01")

      expect(@mock, :request, fn _, _, headers, _ ->
        assert {"anthropic-version", "2024-01-01"} in headers

        response = %{
          "content" => [
            %{
              "text" => JSON.encode!(%{"name" => "Bob", "age" => 35})
            }
          ]
        }

        {:ok, %{status: 200, body: JSON.encode!(response)}}
      end)

      assert {:ok, %{"name" => "Bob", "age" => 35}} = Anthropic.complete(mentor)
    end
  end

  describe "complete!/1" do
    test "raises on error" do
      mentor =
        Mentor.start_chat_with!(Anthropic, schema: TestSchema)
        |> Mentor.configure_adapter(api_key: "test_key", model: "claude-3-5-sonnet-20241022")
        |> Mentor.configure_http_client(@mock)
        |> Mentor.append_message(%{role: "user", content: "Test"})

      expect(@mock, :request, fn _, _, _, _ ->
        {:error, :connection_refused}
      end)

      assert_raise RuntimeError, ~r/HTTP request failed/, fn ->
        Anthropic.complete!(mentor)
      end
    end
  end
end
