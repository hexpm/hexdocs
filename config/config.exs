import Config

config :hexdocs,
  port: "4002",
  hexpm_url: "http://localhost:4000",
  hexpm_secret: "2cd6d09334d4b00a2be4d532342b799b",
  typesense_url: "http://localhost:8108",
  typesense_api_key: "hexdocs",
  typesense_collection: "hexdocs",
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Local,
  cdn_impl: Hexdocs.CDN.Local,
  search_impl: Hexdocs.Search.Local,
  source_repo_impl: Hexdocs.SourceRepo.GitHub,
  tmp_dir: "tmp",
  queue_id: "test",
  queue_producer: Broadway.DummyProducer,
  queue_concurrency: 1,
  session_key_base: "9doqKjmNsklcWmv1+779E2su++ejdBhnSYgqAiGgwtAPpdVf4ns5eXi4IOZk1Eoi",
  session_signing_salt: "QftsNdJO",
  session_encryption_salt: "QftsNdJO",
  host: "localhost",
  gcs_put_debounce: 0,
  special_packages: %{
    "eex" => "elixir-lang/elixir",
    "elixir" => "elixir-lang/elixir",
    "ex_unit" => "elixir-lang/elixir",
    "iex" => "elixir-lang/elixir",
    "logger" => "elixir-lang/elixir",
    "mix" => "elixir-lang/elixir",
    "hex" => "hexpm/hex"
  }

config :hexdocs, :repo_bucket, name: "staging.s3.hex.pm"

config :hexdocs, :docs_private_bucket, name: "hexdocs-private-staging"

config :hexdocs, :docs_public_bucket, name: "hexdocs-public-staging"

config :logger, :console, format: "[$level] $metadata$message\n"

import_config "#{Mix.env()}.exs"
