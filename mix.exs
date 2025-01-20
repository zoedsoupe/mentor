defmodule Mentor.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/zoedsoupe/mentor"

  def project do
    [
      app: :mentor,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url,
      dialyzer: [plt_local_path: "priv/plts", ignore_warnings: ".dialyzerignore"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mentor.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:finch, "~> 0.19"},
      {:nimble_options, "~> 1.1"},
      {:ecto, "~> 3.12", optional: true},
      {:peri, "~> 0.3", optional: true},
      {:mox, "~> 1.2", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "A Plug'n Play instructor implementation in Elixir, leveraging composability and extensibility"
  end

  defp package do
    [
      name: "mentor",
      links: %{"GitHub" => @source_url},
      licenses: ["MIT"]
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
