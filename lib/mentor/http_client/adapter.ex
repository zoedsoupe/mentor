defmodule Mentor.HTTPClient.Adapter do
  @moduledoc """
  Defines the behaviour for HTTP client adapters within the Mentor framework.

  This module specifies a set of callbacks that any HTTP client adapter must implement to integrate seamlessly with Mentor. By adhering to this behaviour, developers can create custom adapters that handle HTTP requests and responses according to their specific requirements.

  ## Callbacks

  - `request/2`: Initiates an HTTP request based on the provided `Mentor` struct and options.
  - `stream/2` (optional): Initiates a streaming HTTP request.
  - `stream/3` (optional): Initiates a streaming HTTP request with a callback for processing each response chunk.

  ## Types

  - `status`: Represents the HTTP status code as an integer.
  - `headers`: A list of tuples containing header names and values.
  - `body`: The response body as a binary.
  - `response`: The HTTP response, typically represented by `Finch.Response.t()`.

  ## Usage

  To implement a custom HTTP client adapter, define a module that implements the `Mentor.HTTPClient.Adapter` behaviour:

      defmodule MyApp.HTTPClient.CustomAdapter do
        @behaviour Mentor.HTTPClient.Adapter

        @impl true
        def request(%Mentor{} = mentor, opts) do
          # Implementation for processing the mentor struct and options
        end

        @impl true
        def stream(%Mentor{} = mentor, opts) do
          # Optional implementation for streaming requests
        end

        @impl true
        def stream(%Mentor{} = mentor, on_response, opts) do
          # Optional implementation for streaming requests with a response callback
        end
      end

  By implementing these callbacks, your custom adapter can be utilized within the Mentor framework to handle HTTP interactions.

  ## Considerations

  - **Optional Callbacks**: The `stream/2` and `stream/3` callbacks are optional. If your adapter does not support streaming, you may omit these implementations.
  - **Error Handling**: Ensure that your adapter appropriately handles errors and returns `{:error, reason}` tuples when necessary.
  - **Integration**: Custom adapters allow Mentor to interface with various HTTP clients, such as [Mint](https://github.com/elixir-mint/mint), [Finch](https://github.com/sneako/finch), or [Tesla](https://github.com/elixir-tesla/tesla), providing flexibility in choosing the underlying HTTP client library.

  By following this behaviour, developers can create flexible and interchangeable HTTP client adapters that integrate seamlessly with the Mentor framework.
  """

  @type url :: String.t() | URI.t()
  @type status :: integer
  @type headers :: list({name :: String.t(), value :: String.t()})
  @type body :: map
  @type request_opts :: keyword

  @callback request(url, body, headers, request_opts) :: {:ok, term} | {:error, term}
end
