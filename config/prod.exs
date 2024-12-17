import Config

config :hexdocs,
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Impl,
  cdn_impl: Hexdocs.CDN.Fastly,
  search_impl: Hexdocs.Search.Typesense,
  queue_producer: BroadwaySQS.Producer,
  gcs_put_debounce: 3000

config :hexdocs, :repo_bucket, implementation: Hexdocs.Store.S3

config :hexdocs, :docs_private_bucket, implementation: Hexdocs.Store.GS

config :hexdocs, :docs_public_bucket, implementation: Hexdocs.Store.GS

config :ex_aws,
  json_codec: Jason

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  before_send: {Hexdocs.Application, :sentry_before_send}

config :sasl, sasl_error_logger: false

config :logger, level: :info
config :logger, :default_formatter, metadata: [:request_id]
