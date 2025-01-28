defmodule Mentor.HTTPClient.Finch do
  @moduledoc """
  An HTTP client adapter for the Mentor framework, utilizing the Finch library for efficient and performant HTTP requests.

  This module implements the `Mentor.HTTPClient.Adapter` behaviour, providing the necessary functions to handle HTTP requests within the Mentor framework using Finch. Finch is an HTTP client focused on performance, built on top of Mint and NimblePool. [oai_citation_attribution:1‡GitHub](https://github.com/sneako/finch?utm_source=chatgpt.com)

  ## Usage

  To use this adapter, ensure that Finch is started and configured appropriately in your application. Typically, you'll add Finch to your supervision tree:

      children = [
        {Finch, name: Mentor.Finch}
      ]

  With Finch running, the `Mentor.HTTPClient.Finch` module can handle HTTP requests as defined by the `Mentor.HTTPClient.Adapter` behaviour.

  ## Considerations

  - **Finch Configuration**: Ensure that Finch is properly configured and started in your application's supervision tree to handle HTTP requests effectively.

  - **Request Options**: The `request/2` function accepts a keyword list of options that are passed to Finch's `request/3` function. Refer to Finch's documentation for details on available options and their effects. [oai_citation_attribution:0‡HexDocs](https://hexdocs.pm/finch/Finch.html?utm_source=chatgpt.com)

  - **Error Handling**: Implement appropriate error handling in your application to manage potential issues during HTTP requests, such as network errors or unexpected responses.

  By leveraging Finch, this adapter provides a high-performance HTTP client solution within the Mentor framework, suitable for applications requiring efficient HTTP interactions.
  """

  @behaviour Mentor.HTTPClient.Adapter

  @impl true
  def request(url, body, headers, opts \\ []) do
    body = JSON.encode_to_iodata!(body)

    :post
    |> Finch.build(url, headers, body, opts)
    |> Finch.request(Mentor.Finch)
  end
end
