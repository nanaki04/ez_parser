defmodule EzParser.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ez_parser,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.16", only: [:dev], runtime: false},
      {:code_parser_state, git: "https://github.com/nanaki04/code_parser_state.git"},
    ]
  end
end
