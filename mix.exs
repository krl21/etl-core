defmodule EtlCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :etl_core,
      version: "1.2.0",
      elixir: "~> 1.14.0-rc.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
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
      links: %{"Bitbucket" => "https://bitbucket.org/teamdox/etl-core"},
      description: "Base functions for ETL process"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.7.8"},
      {:poison, "~> 5.0"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 1.8.2"},
      {:decorator, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:amqp, "~> 3.2"},
      {:ecto_sql, "~> 3.9.0"},
      {:postgrex, "~> 0.16.0"},
      {:nimble_pool, "~> 1.0"},
      {:poolboy, "~> 1.5"},
      {:goth, "~> 1.4"},
      # finch >= 0.22, mint >= 1.9.2 and hpax >= 1.0.4 require Elixir 1.15; the image uses Elixir 1.14
      {:finch, "~> 0.21.0"},
      {:mint, "1.9.1"},
      {:hpax, "1.0.3"},
      # GCS client (Connection.Gcs), with the hackney adapter
      {:tesla, "~> 1.22"}
    ]
  end
end
