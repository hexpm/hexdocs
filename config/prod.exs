use Mix.Config

config :hexdocs,
  port: "${HEXDOCS_PORT}",
  hexpm_url: "${HEXDOCS_HEXPM_URL}",
  hexpm_secret: "${HEXDOCS_HEXPM_SECRET}",
  queue_name: "${HEXDOCS_QUEUE_NAME}",
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Impl,
  cdn_impl: Hexdocs.CDN.Fastly,
  fastly_key: "${HEXDOCS_FASTLY_KEY}",
  fastly_hexdocs: "${HEXDOCS_FASTLY_HEXDOCS}",
  session_key_base: "${HEXDOCS_SESSION_KEY_BASE}",
  session_signing_salt: "${HEXDOCS_SESSION_SIGNING_SALT}",
  session_encryption_salt: "${HEXDOCS_SESSION_ENCRYPTION_SALT}",
  host: "${HEXDOCS_HOST}"

config :hexdocs, :repo_bucket,
  name: "${HEXDOCS_REPO_BUCKET}",
  implementation: Hexdocs.Store.S3

config :hexdocs, :docs_private_bucket,
  name: "${HEXDOCS_DOCS_PRIVATE_BUCKET}",
  implementation: Hexdocs.Store.GS

config :hexdocs, :docs_public_bucket,
  name: "${HEXDOCS_DOCS_PUBLIC_BUCKET}",
  implementation: Hexdocs.Store.GS

config :ex_aws,
  access_key_id: "${HEXDOCS_AWS_ACCESS_KEY_ID}",
  secret_access_key: "${HEXDOCS_AWS_ACCESS_KEY_SECRET}",
  json_codec: Jason

config :goth, json: {:system, "HEXDOCS_GCP_CREDENTIALS"}

config :rollbax,
  access_token: "${HEXDOCS_ROLLBAR_ACCESS_TOKEN}",
  environment: to_string(Mix.env()),
  enabled: true,
  enable_crash_reports: true

config :sasl, sasl_error_logger: false

config :logger, :console, format: "$time $metadata[$level] $message\n"

config :logger, level: :info
