defmodule Mentor.Ecto.Type do
  @moduledoc """
  `Mentor.Ecto.Type` is a behaviour that lets your implement your own custom `Ecto.Type`
    that works natively with Instructor.

  ## Example
      
  ```elixir
  defmodule MyCustomType do
    use Ecto.Type
    use Mentor.Ecto.Type

    # ... See `Ecto.Type` for implementation details

    def to_json_schema do
      %{
        type: "string",
        format: "email"
      }
    end
  end
  ```
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Mentor.Ecto.Type
    end
  end

  @callback to_json_schema :: map
end
