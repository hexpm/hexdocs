defmodule Hexdocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexdocs,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:eex, :logger, :runtime_tools],
      mod: {Hexdocs.Application, []}
    ]
  end

  defp deps do
    [
      {:distillery, "~> 2.0", runtime: false},
      {:broadway, "~> 0.3.0", github: "plataformatec/broadway", override: true},
      {:broadway_sqs, "~> 0.2.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sqs, "~> 2.0"},
      {:goth, "~> 1.0"},
      {:hackney, "~> 1.13"},
      {:jason, "~> 1.1"},
      {:logster, "~> 0.9.0"},
      {:mox, "~> 0.4.0", only: :test},
      {:plug_cowboy, "~> 2.0"},
      {:rollbax, "~> 0.9.2"},
      {:sweet_xml, "~> 0.6.5"}
    ]
  end
end
