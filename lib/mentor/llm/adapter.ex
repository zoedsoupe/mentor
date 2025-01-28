defmodule Mentor.LLM.Adapter do
  @moduledoc """
  Defines the behaviour for Large Language Model (LLM) adapters within the Mentor framework.

  This module specifies the required callbacks that any LLM adapter must implement to integrate seamlessly with Mentor. It also provides utility functions to assist in verifying and using these adapters.

  ## Callbacks

  - `complete/1`: Processes a `Mentor` struct and returns a result.
  - `complete!/1`: Similar to `complete/1` but raises an exception in case of an error.

  ## Usage

  To create a custom LLM adapter, define a module that implements the `Mentor.LLM.Adapter` behaviour:

      defmodule MyApp.LLM.CustomAdapter do
        use Mentor.LLM.Adapter

        @impl true
        def complete(%Mentor{} = mentor) do
          # Implementation for processing the mentor struct
        end
      end

  `complete!/1` is automatic derived and implemented for you, but you can safely override it if needed.

  By implementing these callbacks, your custom adapter can be utilized within the Mentor framework to handle LLM interactions.
  """

  @doc """
  Callback to process a `Mentor` struct and return a result.

  ## Parameters

  - `mentor`: A `Mentor` struct containing the state and configuration for the LLM interaction.

  ## Returns

  - `{:ok, result}`: On successful processing.
  - `{:error, reason}`: If an error occurs during processing.

  Implement this callback in your adapter module to define how the LLM interaction should be handled.
  """
  @callback complete(Mentor.t()) :: {:ok, term} | {:error, term}
  @callback complete!(Mentor.t()) :: term

  @doc """
  Checks if the given module implements the `Mentor.LLM.Adapter` behaviour.

  ## Parameters

  - `module`: The module to be checked.

  ## Returns

  - `true` if the module implements the behaviour.
  - `false` otherwise.

  ## Examples

      iex> Mentor.LLM.Adapter.impl_by?(MyApp.LLM.CustomAdapter)
      true

      iex> Mentor.LLM.Adapter.impl_by?(String)
      false
  """
  def impl_by?(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      callbacks = __MODULE__.behaviour_info(:callbacks)
      functions = module.__info__(:functions)

      Enum.empty?(callbacks -- functions)
    end
  end

  @doc """
  Macro to be used when implementing the `Mentor.LLM.Adapter` behaviour.

  This macro sets up the necessary boilerplate for defining an adapter, including the `@behaviour` attribute and a default implementation for `complete!/1` that raises an exception on error.

  ## Usage

      defmodule MyApp.LLM.CustomAdapter do
        use Mentor.LLM.Adapter

        @impl true
        def complete(%Mentor{} = mentor) do
          # Implementation for processing the mentor struct
        end
      end

  By using this macro, your module declares adherence to the `Mentor.LLM.Adapter` behaviour and provides a default implementation for `complete!/1`.
  """
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
