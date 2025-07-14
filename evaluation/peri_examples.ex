defmodule PeriExamples do
  @moduledoc """
  Examples demonstrating Mentor with various Peri schema types.
  """

  alias Mentor.LLM.Adapters.OpenAI

  @doc """
  Example with a map schema for product information.
  """
  def run_product_schema do
    product_schema = %{
      name: {:required, :string},
      price: {:required, {:float, {:gt, 0}}},
      currency: {:required, {:enum, ["USD", "EUR", "GBP"]}},
      in_stock: :boolean,
      category: {:string, {:max, 50}},
      tags: {:list, :string}
    }

    Mentor.start_chat_with!(OpenAI, schema: product_schema, max_retries: 3)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Generate product information for a high-end mechanical keyboard"
    })
    |> Mentor.complete()
  end

  @doc """
  Example with a list schema for generating todo items.
  """
  def run_todo_list do
    # Schema for a list of todo items, each with a max length
    todo_schema = {:list, {:string, {:max, 100}}}

    Mentor.start_chat_with!(OpenAI, schema: todo_schema, max_retries: 2)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Create a todo list for launching a new Elixir open source library"
    })
    |> Mentor.complete()
  end

  @doc """
  Example with nested map schema for user profile with address.
  """
  def run_user_profile do
    user_schema = %{
      username: {:required, {:string, {:regex, ~r/^[a-zA-Z0-9_]+$/}}},
      email: {:required, {:string, {:regex, ~r/@/}}},
      age: {:integer, {:range, {18, 120}}},
      bio: {:string, {:max, 500}},
      address: %{
        street: :string,
        city: {:required, :string},
        country: {:required, :string},
        postal_code: {:string, {:regex, ~r/^[A-Z0-9\s-]+$/i}}
      },
      skills: {:list, {:enum, ["Elixir", "Phoenix", "LiveView", "OTP", "Ecto", "GraphQL", "REST"]}}
    }

    Mentor.start_chat_with!(OpenAI, schema: user_schema, max_retries: 3)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Generate a user profile for a senior Elixir developer from Germany"
    })
    |> Mentor.complete()
  end

  @doc """
  Example with tuple schema for coordinates.
  """
  def run_coordinates do
    # Tuple of [latitude, longitude]
    coord_schema = {:tuple, [{:float, {:range, {-90.0, 90.0}}}, {:float, {:range, {-180.0, 180.0}}}]}

    Mentor.start_chat_with!(OpenAI, schema: coord_schema, max_retries: 2)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "What are the coordinates of the Eiffel Tower in Paris? Return as [latitude, longitude]"
    })
    |> Mentor.complete()
  end

  @doc """
  Example with enum schema for multiple choice.
  """
  def run_sentiment_analysis do
    sentiment_schema = {:enum, ["positive", "negative", "neutral", "mixed"]}

    Mentor.start_chat_with!(OpenAI, schema: sentiment_schema, max_retries: 1)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Analyze the sentiment of this review: 'The product works well but the shipping was terrible and took forever.'"
    })
    |> Mentor.complete()
  end

  @doc """
  Example with complex nested structure for API response.
  """
  def run_api_response do
    api_response_schema = %{
      status: {:required, {:enum, ["success", "error", "pending"]}},
      data: {:either, 
        {%{
          id: {:required, :integer},
          result: :string,
          metadata: {:map, :string}
        }, 
        %{
          error_code: {:required, :string},
          error_message: {:required, :string},
          retry_after: :integer
        }}
      },
      timestamp: {:required, :datetime}
    }

    Mentor.start_chat_with!(OpenAI, schema: api_response_schema, max_retries: 2)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Generate a successful API response for a weather query"
    })
    |> Mentor.complete()
  end

  @doc """
  Run all examples and display results.
  """
  def run_all do
    examples = [
      {"Product Schema", &run_product_schema/0},
      {"Todo List", &run_todo_list/0},
      {"User Profile", &run_user_profile/0},
      {"Coordinates", &run_coordinates/0},
      {"Sentiment Analysis", &run_sentiment_analysis/0},
      {"API Response", &run_api_response/0}
    ]

    Enum.each(examples, fn {name, func} ->
      IO.puts("\n=== Running #{name} ===")
      
      case func.() do
        {:ok, result} ->
          IO.puts("Success!")
          IO.inspect(result, pretty: true, limit: :infinity)
          
        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end
      
      # Small delay between examples
      Process.sleep(1000)
    end)
  end
end