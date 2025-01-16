defmodule Mentor do
  @moduledoc false

  alias Mentor.LLM.Adapters.OpenAI
  alias Mentor.Message

  @type t :: %__MODULE__{
          schema: module,
          adapter: OpenAI | module,
          messages: list(Message.t())
        }

  defstruct [:schema, adapter: OpenAI, messages: []]

  defguard is_llm_adapter(llm) when llm in [OpenAI] or is_atom(llm)

  @initial_prompt """
  You are a highly intelligent and skilled assistant. Your task is to analyze and understand the content provided, then generate well-structured outputs that adhere to the constraints and requirements specified in the subsequent instructions. Your responses must be accurate, concise, and match the intended structure or purpose.

  Focus on:
  - Parsing raw input effectively.
  - Generating outputs that are consistent with expectations.
  - Handling complex or ambiguous information with clarity and precision.
  - Following all constraints and guidelines provided in the forthcoming messages.

  Be ready to process and transform inputs into structured, actionable results as required.
  """

  @doc """
  Starts a new interaction pipeline based on a schema.

  ## Examples
      iex> Mentor.start_chat_with(Mentor.LLM.OpenAI, schema: MySchema)
      %Mentor{adapter: Mentor.LLM.OpenAI, schema: MySchema, messages: []}
  """
  def start_chat_with(adapter, schema: schema)
      when is_llm_adapter(adapter) and is_atom(schema) do
    %__MODULE__{schema: schema}
  end

  @doc """
  Adds a new message to the chain.
  """
  def append_message(%__MODULE__{} = mentor, %{} = message) do
    %{mentor | messages: [message | mentor.messages]}
  end

  @doc """
  Completes an interaction based on the provided schema and messages.

  ## Parameters
    - builder: The `Mentor.MessageBuilder` instance.
    - schema: The schema to validate against.
    - options: Additional configuration.

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure
  """
  @spec complete(t) :: {:ok, struct} | {:error, term}
  def complete(%__MODULE__{adapter: adapter} = mentor)
      when not is_nil(mentor.schema) do
    with :ok <- validate_ecto_schema(mentor),
         {:ok, doc} <- validate_documentation(mentor),
         :ok <- adapter.validate_config(adapter.config),
         mentor = append_message(mentor, %{role: "user", content: doc}),
         mentor = append_message(mentor, %{role: "system", content: @initial_prompt}),
         {:ok, messages} <- validate_messages(mentor) do
      messages
    end
  end

  defp validate_ecto_schema(%__MODULE__{schema: schema}) do
    if function_exported?(schema, :__schema__, 1) do
      :ok
    else
      {:error, :not_ecto_schema}
    end
  end

  defp validate_documentation(%__MODULE__{schema: schema}) do
    if function_exported?(schema, :__mentor_schema_documentation__, 0) do
      {:ok, schema.__mentor_schema_documentation__()}
    else
      {:error, :no_mentor_documentation}
    end
  end

  defp validate_messages(%__MODULE__{messages: messages, adapter: adapter})
       when is_list(messages) do
    messages
    |> Enum.reduce_while([], fn message, acc ->
      case Message.new(message, for: adapter) do
        {:ok, message} -> {:cont, acc ++ [message]}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> then(fn
      messages when is_list(messages) -> {:ok, messages}
      err -> err
    end)
  end
end
