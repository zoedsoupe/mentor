defmodule Mentor.LLM.Adapter do
  @moduledoc false

  # TODO parse and restrict errors to specific atoms
  @callback complete(Mentor.t()) :: {:ok, term} | {:error, term}
  @callback complete!(Mentor.t()) :: term

  @callback validate_config(map) :: :ok | {:error, Ecto.Changeset.t()}

  @callback parse_message_content(content) :: {:ok, map} | {:error, Ecto.Changeset.t()}
            when content: map

  @doc """
  Same behaviour from `Protocol.impl_for/1` but instead
  to return the impl module, returns `true` if the provided module
  implements this behaviour and `false` if not.
  """
  def impl_by?(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module) do
      callbacks = __MODULE__.behaviour_info(:callbacks)
      functions = module.__info__(:functions)

      Enum.empty?(callbacks -- functions)
    end
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Mentor.LLM.Adapter

      @doc """
      Same as `complete/1` but raises an exception in case of error
      """
      @impl true
      def complete!(%Mentor{} = mentor) do
        case complete(mentor) do
          {:ok, data} -> data
          {:error, err} -> raise inspect(err, pretty: true)
        end
      end

      defoverridable Mentor.LLM.Adapter
    end
  end
end
