defmodule Mentor.HTTPClient.Adapter do
  @moduledoc false

  @type status :: integer
  @type headers :: list({name :: String.t(), value :: String.t()})
  @type body :: binary
  @type response :: Finch.Response.t()

  @callback request(Mentor.t(), request_opts :: keyword) :: {:ok, response} | {:error, term}
  @callback stream(Mentor.t(), request_opts :: keyword) :: {:ok, response} | {:error, term}
  @callback stream(Mentor.t(), on_response, request_opts :: keyword) ::
              {:ok, response} | {:error, term}
            when on_response: ({status, headers, body} -> term)

  @optional_callbacks stream: 2, stream: 3
end
