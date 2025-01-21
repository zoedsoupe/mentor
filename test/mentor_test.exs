defmodule MentorTest do
  use ExUnit.Case, async: true

  import Mox

  alias Mentor.LLM.Adapters.OpenAI

  Code.compile_file(Path.expand("./evaluation/schema.ex"))

  setup :verify_on_exit!

  @mock TestHTTPClient

  setup_all do
    opts = [
      schema: Schema,
      adapter_config: [api_key: "hehe", model: "gpt-4o-mini"],
      http_client: @mock
    ]

    {:ok, mentor: Mentor.start_chat_with!(OpenAI, opts)}
  end

  test "start_chat_with!/2 initializes Mentor struct correctly" do
    schema = Schema
    adapter = OpenAI
    config = [model: "gpt-4", api_key: "test_key"]

    mentor = Mentor.start_chat_with!(adapter, schema: schema, adapter_config: config)

    assert %Mentor{
             __schema__: ^schema,
             adapter: ^adapter,
             config: ^config,
             max_retries: 3,
             debug: false
           } = mentor
  end

  test "append_message/2 adds a new message to the messages list", %{mentor: mentor} do
    message = %{role: "user", content: "Hello, assistant!"}

    updated_mentor = Mentor.append_message(mentor, message)

    assert [%{role: "user", content: "Hello, assistant!"}] = updated_mentor.messages
  end

  describe "complete/1" do
    test "processes successful response correctly", %{mentor: mentor} do
      @mock
      |> expect(:request, fn _url, _body, _headers, _opts ->
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
  end
end
