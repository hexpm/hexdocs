import Config

config :hexdocs,
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Impl,
  cdn_impl: Hexdocs.CDN.Fastly,
  queue_producer: BroadwaySQS.Producer

config :hexdocs, :repo_bucket, implementation: Hexdocs.Store.S3

config :hexdocs, :docs_private_bucket, implementation: Hexdocs.Store.GS

config :hexdocs, :docs_public_bucket, implementation: Hexdocs.Store.GS

config :ex_aws,
  json_codec: Jason

config :rollbax,
  environment: "prod",
  enabled: true,
  enable_crash_reports: true

config :sasl, sasl_error_logger: false

config :logger,
  level: :info,
  metadata: [:request_id]
