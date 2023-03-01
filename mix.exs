defmodule EtlCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :etl_core,
      version: "0.1.0",
      elixir: "~> 1.14.0-rc.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      {:timex, "~> 3.7.8"},
      {:poison, "~> 5.0"},
      {:httpoison, "~> 1.8.2", override: true},

    ]
  end
end
