defmodule Schema do
  # @moduledoc "ANOTHER WTF WOW\n\n## Fields\n- `name`: my name\n- `age`: my\nage\nbecause\ni'm\nvery **old**"

  # @moduledoc since: "v1.0.0"

  use Ecto.Schema
  use Mentor.Ecto.Schema, ignored_fields: [:timestamps, :context]

  import Ecto.Changeset

  @timestamps_opts [inserted_at: :created_at]

  @primary_key false
  embedded_schema do
    field :name, :string
    field :age, :integer

    field :context, :map, default: %{}

    # that doesn't works :/
    # timestamps(inserted_at: :created_at)
  end

  @impl true
  def changeset(%__MODULE__{} = source, %{} = attrs) do
    source
    |> cast(attrs, [:name, :age])
    |> validate_required([:name, :age])
    |> validate_number(:age, less_than_or_equal_to: 100, greater_than_or_equal_to: 0)
  end

  @impl true
  def llm_description do
    """
    ## Fields

    - `name`: it should be a valid string name for humans
    - `age`: it should be a reasonable age number for a human being
    """
  end
end
