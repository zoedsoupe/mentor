defmodule Schema do
  @moduledoc "ANOTHER WTF WOW\n\n## Fields\n- `name`: my name\n- `age`: my\nage\nbecause\ni'm\nvery **old**"

  @moduledoc since: "v1.0.0"

  use Ecto.Schema
  use Mentor.Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :age, :integer
  end

  @impl true
  def changeset(%__MODULE__{} = source, %{} = attrs) do
    source
    |> cast(attrs, [:name, :age])
    |> validate_required([:name, :age])
    |> validate_number(:age, less_than: 100, greater_than: 0)
  end
end
