defmodule Hexdocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexdocs,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :plug_crypto],
      mod: {Hexdocs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:distillery, "~> 2.0", runtime: false},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sqs, "~> 2.0"},
      {:gen_stage, "~> 0.14.0"},
      {:goth, "~> 0.9.0"},
      {:hackney, "~> 1.13"},
      {:jason, "~> 1.1"},
      {:logster, "~> 0.9.0"},
      {:mox, "~> 0.4.0"},
      {:plug_cowboy, "~> 2.0"},
      {:poison, "~> 3.1"},
      {:rollbax, "~> 0.9.2"},
      {:sweet_xml, "~> 0.6.5"}
    ]
  end
end
