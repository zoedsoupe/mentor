defmodule Mentor do
  @moduledoc """
  The `Mentor` module facilitates interactions with Large Language Models (LLMs) by managing conversation state, configuring adapters, and validating responses against specified schemas.

  ## Features

  - Initiate and manage chat sessions with various LLM adapters.
  - Configure session parameters, including retry limits and debugging options.
  - Validate LLM responses against predefined schemas to ensure data integrity. Supported schemas include `Ecto` schemas, structs, raw maps, `NimbleOptions`, and `Peri` schemas.

  > #### Note {: .warning}
  >
  > For now, until `v0.1.0` only `Ecto` shemas are supported.

  ## Backoff calculation

  If a structured output request fails, `mentor` support retries, defaulting to a max number of 3 retries, that can be overwritten.

  `mentor` also applies by default, an exponential backoff while to execute the next retry attempt, the backoff calculation, that formula is used:

  ```
  min(max_backoff, (base_backoff * 2) ^ retry_count)
  ```

  Example:

  | Attempt | Base Backoff | Max Backoff | Sleep time |
  |---------|--------------|-------------|----------------|
  | 1       | 10           | 30000       | 20 |
  | 2       | 10           | 30000       | 400 |
  | 3       | 10           | 30000       | 8000 |
  | 4       | 10           | 30000       | 30000 |
  | 5       | 10           | 30000       | 30000 |

  > considering the default values for `base_backoff` (1s) and `max_backoff` (5s)

  Those backoff values can be overwritten by using `configure_backoff/2` function.
  """

  alias Mentor.Ecto, as: MentorEcto
  alias Mentor.HTTPClient.Finch
  alias Mentor.LLM.Adapter
  alias Mentor.LLM.Adapters.Gemini
  alias Mentor.LLM.Adapters.OpenAI

  @type message :: %{role: String.t(), content: term}

  @typedoc """
  Represents the state of a Mentor session.

  ## Fields

  - `:__schema__` - The schema module or map defining the expected data structure.
  - `:json_schema` - The JSON schema map derived from the schema, used for validation.
  - `:adapter` - The LLM adapter module responsible for handling interactions.
  - `:initial_prompt` - The initial system prompt guiding the LLM's behavior.
  - `:messages` - A list of messages exchanged in the session.
  - `:config` - Configuration options for the adapter.
  - `:max_retries` - The maximum number of retries allowed for validation failures.
  - `:debug` - A boolean flag indicating whether debugging is enabled.
  - `:http_client` - The HTTP Client that implements the `Mentor.HTTPClient.Adapter` behaviour to be used to dispatch HTTP requests to the LLM adapter.
  - `:timeout` - Configures how the timeout backoff should be applied on retries. Check [Backoff calculation to understand it better](#backoff-calculation)
    - `:max_backoff` - The maximum backoff value in ms, default: `5s`.
    - `:base_backoff` - The base backoff value in ms, default: `1s`.
  """
  @type t :: %__MODULE__{
          __schema__: Mentor.Schema.t() | nil,
          json_schema: map | nil,
          adapter: module,
          initial_prompt: String.t(),
          messages: list(message),
          config: keyword,
          max_retries: integer,
          debug: boolean,
          http_client: module,
          http_config: keyword,
          timeout: list({:max_backoff, non_neg_integer} | {:base_backoff, non_neg_integer})
        }

  defstruct [
    :__schema__,
    :json_schema,
    :initial_prompt,
    :adapter,
    http_client: Finch,
    debug: false,
    max_retries: 3,
    messages: [],
    config: [],
    http_config: [],
    timeout: [
      max_backoff: to_timeout(second: 5),
      base_backoff: to_timeout(second: 1)
    ]
  ]

  defguard is_llm_adapter(llm) when llm in [OpenAI, Gemini] or is_atom(llm)

  @initial_prompt """
  You are a highly intelligent and skilled assistant. Your task is to analyze and understand the content provided, then generate well-structured outputs that adhere to the constraints and requirements specified in the subsequent instructions. Your responses must be accurate, concise, and match the intended structure or purpose.

  Focus on:
  - Parsing raw input effectively.
  - Generating outputs that are consistent with expectations and obey the provided schema.
  - Handling complex or ambiguous information with clarity and precision.
  - Following all constraints and guidelines provided in the forthcoming messages.

  Be ready to process and transform inputs into structured, actionable results as required.
  """

  @doc """
  Starts a new interaction pipeline based on a schema.

  ## Parameters

  - `adapter` - The LLM adapter module to handle interactions (e.g., `Mentor.LLM.Adapters.OpenAI`).
  - `opts` - A keyword list of options:
    - `:schema` - The schema module or map defining the expected data structure, required.
    - `:max_retries` (optional) - The maximum number of retries for validation failures (default: 3).

  ## Examples

      iex> Mentor.start_chat_with!(Mentor.LLM.Adapters.OpenAI, schema: MySchema)
      %Mentor{}

      iex> Mentor.start_chat_with!(UnknownLLMAdapter, schema: MySchema)
      ** (RuntimeError) UnknownLLMAdapter should implement the Mentor.LLM.Adapter behaviour.

      iex> Mentor.start_chat_with!(Mentor.LLM.Adapters.OpenAI, schema: nil)
      ** (RuntimeError) nil should be a valid schema
  """
  @spec start_chat_with!(module, config) :: t
        when config: list(option),
             option: {:max_retries, integer} | {:schema, Mentor.Schema.t()}
  def start_chat_with!(adapter, opts) when is_llm_adapter(adapter) and is_list(opts) do
    schema = Keyword.fetch!(opts, :schema)
    max_retries = Keyword.get(opts, :max_retries, 3)

    if not Adapter.impl_by?(adapter) do
      raise "#{inspect(adapter)} should implement the #{inspect(Adapter)} behaviour."
    end

    if not ecto_schema?(schema) do
      raise "#{inspect(schema)} should be an Ecto.Schema"
    end

    maybe_append_schema_documentation_message(%__MODULE__{
      __schema__: schema,
      initial_prompt: @initial_prompt,
      adapter: adapter,
      max_retries: max_retries,
      http_client: Finch
    })
  end

  @spec ecto_schema?(module) :: boolean
  defp ecto_schema?(schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) do
      function_exported?(schema, :__schema__, 1)
    end
  end

  defp maybe_append_schema_documentation_message(%__MODULE__{} = mentor) do
    if documentation = maybe_get_documentation(mentor.__schema__) do
      %{mentor | initial_prompt: Enum.join([mentor.initial_prompt, documentation], "\n")}
    else
      mentor
    end
  end

  @spec maybe_get_documentation(module) :: String.t() | nil
  defp maybe_get_documentation(schema) do
    schema.__mentor_schema_documentation__() || schema.llm_description()
  end

  @doc """
  Overwrites the initial prompt for the LLM session.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `initial_prompt` - A string containing the new initial prompt.

  ## Returns

  - An updated `Mentor` struct with the new initial prompt, overwritten.

  ## Examples

      iex> mentor = %Mentor{}
      iex> new_prompt = "You are a helpful assistant."
      iex> Mentor.overwrite_initial_prompt(mentor, new_prompt)
      %Mentor{initial_prompt: "You are a helpful assistant."}
  """
  @spec overwrite_initial_prompt(t, String.t()) :: t
  def overwrite_initial_prompt(%__MODULE__{} = mentor, initial_prompt \\ "")
      when is_binary(initial_prompt) do
    maybe_append_schema_documentation_message(%{mentor | initial_prompt: initial_prompt})
  end

  @doc """
  Configures the LLM adapter with the given options.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `config` - A keyword list of configuration options for the adapter.

  ## Returns

  - An updated `Mentor` struct with the merged adapter configuration.

  ## Examples

      iex> mentor = %Mentor{config: [model: "gpt-3.5"]}
      iex> new_config = [temperature: 0.7]
      iex> Mentor.configure_adapter(mentor, new_config)
      %Mentor{config: [model: "gpt-3.5", temperature: 0.7]}
  """
  @spec configure_adapter(t, keyword) :: t
  def configure_adapter(%__MODULE__{} = mentor, config) when is_list(config) do
    %{mentor | config: Keyword.merge(mentor.config || [], config)}
  end

  @doc """
  Configures the exponential backoff values to be used on retry attempts in case of failed requests.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `config` - A keyword list of configuration options for the backoff.
    - `:max_backoff` - the max value of the backoff can wait in ms, defaults to 5s
    - `:base_backoff` - the base value of the backoff can wait in ms, default to 1s

  ## Returns

  - An updated `Mentor` struct with the merged bacoff configuration.

  ## Examples

      iex> mentor = %Mentor{config: [model: "gpt-3.5"]}
      iex> backoff = [max_backoff: to_timeout(second: 10)]
      iex> Mentor.configure_backoff(mentor, backoff)
      %Mentor{config: [model: "gpt-3.5"], timeout: [max_backoff: 10_000, base_backoff: 1_000]}
  """
  @spec configure_backoff(t, keyword) :: t
  def configure_backoff(%__MODULE__{} = mentor, config) when is_list(config) do
    max_backoff = config[:max_backoff] || to_timeout(second: 5)
    base_backoff = config[:base_backoff] || to_timeout(second: 1)
    %{mentor | timeout: [max_backoff: max_backoff, base_backoff: base_backoff]}
  end

  @doc """
  Configures the underlying HTTP client used to make request, with the given options.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `http_client` - The HTTP client to use underlying, needs to implement the `#{inspect(Adapter)}` behaviour and default to the `Mentor.HTTPClient.Finch`.
  - `config` - A keyword list of configuration options for the underlying HTTP client.

  ## Returns

  - An updated `Mentor` struct with the chosen HTTP client and its config.

  ## Examples

      iex> mentor = %Mentor{http_client: Mentor.HTTPClient.Finch, http_config: []}
      iex> config = [request_timeout: 50_000]
      iex> Mentor.configure_http_client(mentor, MyReqAdapter, config)
      %Mentor{http_client: MyReqAdapter, http_config: ^config}

      iex> mentor = %Mentor{http_client: Mentor.HTTPClient.Finch, http_config: []}
      iex> config = [request_timeout: 50_000]
      iex> Mentor.configure_http_client(mentor, config)
      %Mentor{http_client: Mentor.HTTPClient.Finch, http_config: ^config}

      iex> mentor = %Mentor{http_client: Mentor.HTTPClient.Finch, http_config: []}
      iex> Mentor.configure_http_client(mentor, MyReqAdapter)
      %Mentor{http_client: MyReqAdapter, http_config: []}
  """
  @spec configure_http_client(t, http_client :: module, config :: keyword) :: t
  def configure_http_client(%__MODULE__{} = mentor, client \\ Finch, config \\ [])
      when is_list(config) do
    %{mentor | http_config: config, http_client: client}
  end

  @doc """
  Sets the maximum number of retries for validation failures.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `max` - An integer specifying the maximum number of retries.

  ## Returns

  - An updated `Mentor` struct with the new `max_retries` value.

  ## Examples

      iex> mentor = %Mentor{max_retries: 3}
      iex> Mentor.define_max_retries(mentor, 5)
      %Mentor{max_retries: 5}
  """
  @spec define_max_retries(t, integer) :: t
  def define_max_retries(%__MODULE__{} = mentor, max) when is_integer(max) do
    %{mentor | max_retries: max}
  end

  @doc """
  Adds a new message to the conversation history.

  ## Parameters

  - `mentor` - The current `Mentor` struct.
  - `message` - A map representing the message to be added, typically containing:
    - `:role` - The role of the message sender (e.g., "user", "assistant", "system", "developer").
    - `:content` - The content of the message (e.g. a raw string).

  ## Returns

  - An updated `Mentor` struct with the new message appended to the `messages` list.

  ## Examples

      iex> mentor = %Mentor{}
      iex> message = %{role: "user", content: "Hello, assistant!"}
      iex> Mentor.append_message(mentor, message)
      %Mentor{messages: [%{role: "user", content: "Hello, assistant!"}]}
  """
  @spec append_message(t, map) :: t
  def append_message(%__MODULE__{} = mentor, %{} = message) do
    # yeah, prepending but on `complete/1` we'll reverse the history
    %{mentor | messages: [message | mentor.messages]}
  end

  @doc """
  Completes the interaction by sending the accumulated messages to the LLM adapter and processing the response.

  ## Parameters

  - `mentor` - The current `Mentor` struct.

  ## Returns

  - `{:ok, result}` on successful completion, where `result` is the validated and processed response.
  - `{:error, reason}` on failure, with `reason` indicating the cause of the error.

  ## Examples

      iex> mentor = %Mentor{adapter: Mentor.LLM.Adapters.OpenAI, __schema__: MySchema, config: [model: "gpt-4"]}
      iex> Mentor.complete(mentor)
      {:ok, %MySchema{}}

      iex> mentor = %Mentor{adapter: nil, __schema__: MySchema}
      iex> Mentor.complete(mentor)
      {:error, :adapter_not_configured}
  """
  @spec complete(t) :: {:ok, Mentor.Schema.t()} | {:error, term}
  def complete(%__MODULE__{adapter: adapter} = mentor)
      when not is_nil(mentor.__schema__) and not is_nil(mentor.adapter) and is_list(mentor.config) do
    mentor = prepare_prompt(mentor)

    with :ok <- validate_http_client(mentor),
         {:ok, resp} <- adapter.complete(mentor) do
      consume_response(mentor, resp)
    end
  end

  @doc "Same as `complete/1` but it raises an exception if it fails"
  def complete!(%__MODULE__{adapter: adapter, http_client: client} = mentor)
      when not is_nil(mentor.__schema__) and not is_nil(mentor.adapter) and is_list(mentor.config) do
    if not Mentor.HTTPClient.Adapter.impl_by?(client) do
      raise "#{inspect(client)} doesn't implement the #{inspect(Mentor.HTTPClient.Adapter)} behaviour"
    end

    mentor
    |> prepare_prompt()
    |> adapter.complete!()
    |> then(&consume_response(mentor, &1))
    |> then(fn {:ok, data} -> data end)
  end

  defp validate_http_client(%__MODULE__{http_client: client}) do
    if Mentor.HTTPClient.Adapter.impl_by?(client) do
      :ok
    else
      {:error, :configured_http_client_not_supported}
    end
  end

  defp prepare_prompt(%__MODULE__{} = mentor) do
    mandatory = %{role: "system", content: mentor.initial_prompt}
    messages = [mandatory | Enum.reverse(mentor.messages)]
    json_schema = parse_json_schema_from(mentor.__schema__)
    %{mentor | messages: messages, json_schema: json_schema}
  end

  @spec parse_json_schema_from(module | map) :: map
  defp parse_json_schema_from(schema) when is_atom(schema) do
    MentorEcto.JSONSchema.from_ecto_schema(schema)
  end

  defp consume_response(%Mentor{max_retries: max} = m, body) when max == 1 do
    MentorEcto.Schema.validate(m.__schema__, body)
  end

  defp consume_response(%Mentor{max_retries: max} = mentor, body) do
    with {:error, changeset} <- MentorEcto.Schema.validate(mentor.__schema__, body) do
      formatted_errors = MentorEcto.Error.format_errors(changeset)

      mentor
      |> append_message(%{role: "assistant", content: JSON.encode!(body)})
      |> append_message(%{
        role: "system",
        content: """
        The response did not pass validation. Please try again and fix the following validation errors:

        #{formatted_errors}
        """
      })
      |> then(&%{&1 | max_retries: max(0, max - 1)})
      |> then(fn %{timeout: timeout, max_retries: max} = mentor ->
        backoff = calculate_backoff(max, timeout)
        Process.sleep(backoff)
        mentor
      end)
      |> complete()
    end
  end

  defp calculate_backoff(attempt, timeout) do
    max_backoff = timeout[:max_backoff]
    base_backoff = timeout[:base_backoff]

    min(max_backoff, (base_backoff * 2) ** attempt)
  end
end
