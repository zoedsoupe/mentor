defmodule Schema do
  @moduledoc "ANOTHER WTF WOW\n\n## Fields\n- `name`: my name\n- `age`: my\nage\nbecause\ni'm\nvery **old**"

  @moduledoc since: "v1.0.0"

  use Ecto.Schema
  use Mentor.Ecto.Schema

  @primary_key false
  embedded_schema do
    field :name, :string
    field :age, :integer
  end
end
