defmodule NumberSeries do
  @moduledoc """
  ## Fields

  - `series`: an array of integers
  """

  use Ecto.Schema
  use Mentor.Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :series, {:array, :integer}
  end

  @impl true
  def changeset(%__MODULE__{} = number_series, %{} = attrs) do
    number_series
    |> cast(attrs, [:series])
    |> validate_length(:series, min: 10)
    |> validate_change(:series, fn
      field, values ->
        if Enum.sum(values) |> rem(2) == 0 do
          []
        else
          [{field, "The sum of the series must be even"}]
        end
    end)
  end
end
