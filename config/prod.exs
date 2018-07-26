use Mix.Config

config :hexdocs,
  port: {:integer, "${HEXDOCS_PORT}"},
  hexpm_url: "${HEXDOCS_HEXPM_URL}",
  hexpm_secret: "${HEXDOCS_HEXPM_SECRET}",
  queue_name: "${HEXDOCS_QUEUE_NAME}",
  hexpm_impl: Hexpm.Hexpm.Impl,
  store_impl: Hexdocs.Store.Impl,
  session_key_base: "${HEXDOCS_SESSION_KEY_BASE}",
  session_signing_salt: "${HEXDOCS_SESSION_SIGNING_SALT}",
  session_encryption_salt: "${HEXDOCS_SESSION_ENCRYPTION_SALT}",
  host: "${HEXDOCS_HOST}"

config :hexdocs, :repo_bucket,
  name: "${HEXDOCS_REPO_BUCKET}",
  implementation: Hexdocs.Store.S3

config :hexdocs, :docs_bucket,
  name: "${HEXDOCS_DOCS_BUCKET}",
  implementation: Hexdocs.Store.GS

config :ex_aws,
  access_key_id: "${HEXDOCS_AWS_ACCESS_KEY_ID}",
  secret_access_key: "${HEXDOCS_AWS_ACCESS_KEY_SECRET}",
  json_codec: Jason

config :goth, json: {:system, "HEXDOCS_GCP_CREDENTIALS"}
