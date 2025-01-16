defmodule Mentor.HTTPClient.Finch do
  @moduledoc false

  @behaviour Mentor.HTTPClient.Adapter

  @impl true
  def request(%Mentor{} = _mentor, opts \\ []) do
    req = Finch.build(:post, "", [], JSON.encode_to_iodata!(nil))
    Finch.request(req, Mentor.Finch, opts)
  end
end
