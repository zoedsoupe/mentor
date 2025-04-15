defmodule MentorTest do
  use ExUnit.Case, async: true

  import Mox

  alias Mentor.LLM.Adapters.OpenAI
  alias Mentor.LLM.Adapters.Gemini

  Code.compile_file(Path.expand("./evaluation/schema.ex"))

  setup :verify_on_exit!

  @mock TestHTTPClient

  setup_all do
    {:ok,
     mentor:
       Mentor.start_chat_with!(OpenAI, schema: Schema)
       |> Mentor.configure_adapter(api_key: "hehe", model: "gpt-4o-mini")
       |> Mentor.configure_http_client(@mock)
       |> Mentor.define_max_retries(0)
       |> Mentor.configure_backoff(max_backoff: 1, base_backoff: 1),
     gemini_mentor:
       Mentor.start_chat_with!(Gemini, schema: Schema)
       |> Mentor.configure_adapter(api_key: "test_key", model: "gemini-2.0-flash-lite")
       |> Mentor.configure_http_client(@mock)
       |> Mentor.define_max_retries(0)
       |> Mentor.configure_backoff(max_backoff: 1, base_backoff: 1)}
  end

  test "start_chat_with!/2 initializes Mentor struct correctly with OpenAI" do
    schema = Schema
    adapter = OpenAI
    config = [model: "gpt-4", api_key: "test_key"]

    mentor =
      Mentor.start_chat_with!(adapter, schema: schema)
      |> Mentor.configure_adapter(config)

    assert %Mentor{
             __schema__: ^schema,
             adapter: ^adapter,
             config: ^config,
             max_retries: 3,
             debug: false
           } = mentor
  end

  test "start_chat_with!/2 initializes Mentor struct correctly with Gemini" do
    schema = Schema
    adapter = Gemini
    config = [model: "gemini-2.0-flash-lite", api_key: "test_key"]

    mentor =
      Mentor.start_chat_with!(adapter, schema: schema)
      |> Mentor.configure_adapter(config)

    assert %Mentor{
             __schema__: ^schema,
             adapter: ^adapter,
             config: ^config,
             max_retries: 3,
             debug: false
           } = mentor
  end

  test "append_message/2 adds a new message to the messages list with OpenAI", %{mentor: mentor} do
    message = %{role: "user", content: "Hello, assistant!"}

    updated_mentor = Mentor.append_message(mentor, message)

    assert [%{role: "user", content: "Hello, assistant!"}] = updated_mentor.messages
  end

  test "append_message/2 adds multimodal content to the messages list with Gemini", %{
    gemini_mentor: mentor
  } do
    message = %{
      role: "user",
      content: [
        %{
          type: "text",
          text: "Extract information from this image."
        },
        %{
          type: "image_base64",
          data: "base64_data",
          mime_type: "image/jpeg"
        }
      ]
    }

    updated_mentor = Mentor.append_message(mentor, message)

    assert [
             %{
               role: "user",
               content: [
                 %{
                   type: "text",
                   text: "Extract information from this image."
                 },
                 %{
                   type: "image_base64",
                   data: "base64_data",
                   mime_type: "image/jpeg"
                 }
               ]
             }
           ] = updated_mentor.messages
  end

  describe "complete/1" do
    test "processes successful response correctly", %{mentor: mentor} do
      expect(@mock, :request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            choices: [
              %{
                message: %{
                  content: ~s|{"name": "i", "age": 10}|
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)

      assert {:ok, %Schema{}} =
               mentor
               |> Mentor.append_message(%{role: "user", content: "Generate a response."})
               |> Mentor.complete()
    end

    test "processes successful Gemini response correctly", %{gemini_mentor: mentor} do
      expect(@mock, :request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      text: ~s|{"name": "Gemini", "age": 25}|
                    }
                  ]
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)

      assert {:ok, %Schema{name: "Gemini", age: 25}} =
               mentor
               |> Mentor.append_message(%{role: "user", content: "Generate a response."})
               |> Mentor.complete()
    end

    test "retries on validation error", %{mentor: mentor} do
      @mock
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            choices: [
              %{
                message: %{
                  content: ~s|{"name": 123, "age": "uau"}|
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            choices: [
              %{
                message: %{
                  content: ~s|{"name": 123, "age": 99999}|
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            choices: [
              %{
                message: %{
                  content: ~s|{"name": "John", "age": 30}|
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)

      assert {:ok, %Schema{name: "John", age: 30}} =
               mentor
               |> Mentor.append_message(%{role: "user", content: "Generate a response."})
               |> Mentor.complete()
    end

    test "retries on validation error with Gemini", %{gemini_mentor: mentor} do
      @mock
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      text: ~s|{"name": 123, "age": "invalid"}|
                    }
                  ]
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      text: ~s|{"name": "Gemini", "age": 101}|
                    }
                  ]
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)
      |> expect(:request, fn _url, _body, _headers, _opts ->
        body =
          JSON.encode!(%{
            candidates: [
              %{
                content: %{
                  parts: [
                    %{
                      text: ~s|{"name": "Gemini", "age": 30}|
                    }
                  ]
                }
              }
            ]
          })

        {:ok, %Finch.Response{status: 200, headers: [], body: body}}
      end)

      assert {:ok, %Schema{name: "Gemini", age: 30}} =
               mentor
               |> Mentor.append_message(%{role: "user", content: "Generate a response."})
               |> Mentor.complete()
    end
  end
end
