import Config

config :hexdocs,
  port: System.fetch_env!("HEXDOCS_PORT"),
  hexpm_url: System.fetch_env!("HEXDOCS_HEXPM_URL"),
  hexpm_secret: System.fetch_env!("HEXDOCS_HEXPM_SECRET"),
  fastly_key: System.fetch_env!("HEXDOCS_FASTLY_KEY"),
  fastly_hexdocs: System.fetch_env!("HEXDOCS_FASTLY_HEXDOCS"),
  queue_id: System.fetch_env!("HEXDOCS_QUEUE_ID"),
  session_key_base: System.fetch_env!("HEXDOCS_SESSION_KEY_BASE"),
  session_signing_salt: System.fetch_env!("HEXDOCS_SESSION_SIGNING_SALT"),
  session_encryption_salt: System.fetch_env!("HEXDOCS_SESSION_ENCRYPTION_SALT"),
  queue_concurrency: String.to_integer(System.fetch_env!("HEXDOCS_QUEUE_CONCURRENCY")),
  host: System.fetch_env!("HEXDOCS_HOST")

config :hexdocs, :repo_bucket, name: System.fetch_env!("HEXDOCS_REPO_BUCKET")

config :hexdocs, :docs_private_bucket, name: System.fetch_env!("HEXDOCS_DOCS_PRIVATE_BUCKET")

config :hexdocs, :docs_public_bucket, name: System.fetch_env!("HEXDOCS_DOCS_PUBLIC_BUCKET")

config :ex_aws,
  access_key_id: System.fetch_env!("HEXDOCS_AWS_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("HEXDOCS_AWS_ACCESS_KEY_SECRET")

config :rollbax,
  access_token: System.fetch_env!("HEXDOCS_ROLLBAR_ACCESS_TOKEN")

config :kernel,
  inet_dist_listen_min: String.to_integer(System.fetch_env!("BEAM_PORT")),
  inet_dist_listen_max: String.to_integer(System.fetch_env!("BEAM_PORT"))
