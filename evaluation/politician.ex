defmodule Politician do
  @moduledoc """
  A description of Brazilian Politicians and the offices that they held, you can specify only the most relevants held offices in the past 20 years.

  ## Fields

  - `first_name`: Their first name
  - `party`: Theier politic party, the most recent you have knowledge
  - `last_name`: Their last name
  - `offices_held`:
    - `office`: The name of the political office held by the politician (in lowercase)
    - `from_date`: When they entered office (YYYY-MM-DD)
    - `to_date`: The date they left office, if relevant (YYYY-MM-DD or null).
  """

  use Ecto.Schema
  use Mentor.Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :first_name, :string
    field :last_name, :string
    field :party, :string

    embeds_many :offices_held, Office, primary_key: false do
      @offices ~w(president vice_president minister senator deputy governor vice_governor state_secretary state_deputy mayor deputy_mayor city_councilor)a

      field :office, Ecto.Enum, values: @offices
      field :from_date, :date
      field :to_date, :date
    end
  end

  @impl true
  def changeset(%__MODULE__{} = politician, %{} = attrs) do
    politician
    |> cast(attrs, [:first_name, :last_name, :party])
    |> validate_required([:first_name, :last_name])
    |> cast_embed(:offices_held, required: true, with: &offices_held_changeset/2)
  end

  defp offices_held_changeset(offices, %{} = attrs) do
    offices
    |> cast(attrs, [:office, :from_date, :to_date])
    |> validate_required([:office, :from_date, :to_date])
  end
end
