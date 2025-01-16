defmodule Mentor.Message do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Mentor.LLM.Adapter

  @type role :: :user | :assistant | :system | :developer

  @type t :: %__MODULE__{
          role: String.t(),
          content: map
        }

  @primary_key false
  embedded_schema do
    field :content, :map
    field :role, Ecto.Enum, values: ~w[user assistant system developer]a
  end

  def changeset(%__MODULE__{} = message, %{} = attrs) do
    message
    |> cast(attrs, [:role, :content])
    |> validate_required([:role, :content])
  end

  def new(%{} = attrs, for: adapter) when is_atom(adapter) do
    with :ok <- validate_adapter(adapter) do
      %__MODULE__{}
      |> changeset(attrs)
      |> validate_content(adapter)
      |> apply_action(:parse)
    end
  end

  defp validate_adapter(adapter) do
    if Adapter.impl_by?(adapter) do
      :ok
    else
      {:error, :adapter_not_loaded}
    end
  end

  defp validate_content(%{valid?: true} = changeset, adapter) do
    content = get_field(changeset, :content)

    case adapter.parse_message_content(content) do
      {:ok, content} ->
        put_change(changeset, :content, content)

      {:error, %Ecto.Changeset{errors: errors}} ->
        Enum.reduce(errors, changeset, fn {err, {msg, opts}} ->
          add_error(changeset, err, msg, opts)
        end)
    end
  end

  defp validate_content(changeset, _), do: changeset
end
