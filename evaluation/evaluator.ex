defmodule Evaluator do
  alias Mentor.LLM.Adapters.OpenAI

  def run_schema do
    config = [api_key: System.fetch_env!("OPENAI_API_KEY"), model: "gpt-4o-mini"]

    OpenAI
    |> Mentor.start_chat_with!(schema: Schema, max_retries: 1)
    |> Mentor.overwrite_initial_prompt()
    |> Mentor.configure_adapter(config)
    |> Mentor.complete
  end

  def run_number_series do
    Mentor.start_chat_with!(OpenAI, schema: NumberSeries, max_retries: 1)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Give me the first 5 integers"
    })
    |> Mentor.complete
  end

  def run_politician do
    Mentor.start_chat_with!(OpenAI, schema: Politician, max_retries: 5)
    |> Mentor.configure_adapter(
      model: "gpt-4o-mini",
      api_key: System.fetch_env!("OPENAI_API_KEY")
    )
    |> Mentor.append_message(%{
      role: "user",
      content: "Who won the Brazilian 2022 election and what offices have they held over their career?"
    })
    |> Mentor.complete
  end

  @doc """
  Run Peri schema examples if Peri is available.
  """
  def run_peri_examples do
    if Code.ensure_loaded?(Peri) do
      IO.puts("\n=== Running Peri Schema Examples ===")
      PeriExamples.run_all()
    else
      IO.puts("\nPeri is not available. Add {:peri, \"~> 0.2\"} to your dependencies to run these examples.")
    end
  end

  @doc """
  Run all evaluation examples.
  """
  def run_all do
    IO.puts("Running Schema example...")
    IO.inspect(run_schema(), label: "Schema result")
    
    IO.puts("\nRunning NumberSeries example...")
    IO.inspect(run_number_series(), label: "NumberSeries result")
    
    IO.puts("\nRunning Politician example...")
    IO.inspect(run_politician(), label: "Politician result")
    
    run_peri_examples()
  end
end
