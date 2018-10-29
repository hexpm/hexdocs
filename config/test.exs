use Mix.Config

config :hexdocs,
  port: "5002",
  hexpm_url: "http://localhost:5000",
  hexpm_impl: Hexdocs.HexpmMock,
  store_impl: Hexdocs.Store.Local,
  cdn_impl: Hexdocs.CDN.Local,
  tmp_dir: "tmp",
  session_key_base: "9doqKjmNsklcWmv1+779E2su++ejdBhnSYgqAiGgwtAPpdVf4ns5eXi4IOZk1Eoi",
  session_signing_salt: "QftsNdJO",
  session_encryption_salt: "QftsNdJO",
  host: "localhost"

config :hexdocs, :repo_bucket, name: "staging.s3.hex.pm"

config :hexdocs, :docs_private_bucket, name: "hexdocs-private-staging"

config :hexdocs, :docs_public_bucket, name: "hexdocs-public-staging"

config :goth,
  config: %{
    "type" => "service_account",
    "project_id" => "support",
    "token_source" => :oauth_jwt
  }

config :logger, level: :warn
