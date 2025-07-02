defmodule Hexdocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexdocs,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:eex, :logger, :runtime_tools, :inets],
      mod: {Hexdocs.Application, []}
    ]
  end

  defp deps do
    [
      {:broadway, "~> 1.0"},
      {:broadway_sqs, "~> 0.7.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws_sqs, "~> 3.0"},
      {:goth, "~> 1.0"},
      {:hackney, "~> 1.13"},
      {:jason, "~> 1.1"},
      {:logster, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:sentry, "~> 10.8"},
      {:ssl_verify_fun, "~> 1.1", manager: :rebar3, override: true},
      {:sweet_xml, "~> 0.7.0"},
      {:hex_core, "~> 0.11.0"},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp releases() do
    [
      hexdocs: [
        include_executables_for: [:unix],
        reboot_system_after_config: true
      ]
    ]
  end
end
