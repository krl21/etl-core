defmodule EtlCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :etl_core,
      version: "0.1.54",
      elixir: "~> 1.14.0-rc.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :odbc]
    ]
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README.md"],
      maintainers: ["Carlos Leon"],
      licenses: ["Apache License 2.0"],
      links: %{"Bitbucket" => "https://bitbucket.org/teamdox/etl-core/src/master/"},
      description: "Base functions for ETL process"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.7.8"},
      {:poison, "~> 5.0"},
      {:httpoison, "~> 1.8.2"},
      {:decorator, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:amqp, "~> 3.2"},

    ]
  end
end
