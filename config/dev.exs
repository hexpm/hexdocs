use Mix.Config

config :hexdocs,
  port: 4002,
  hexpm_url: "http://localhost:4000",
  hexpm_secret: "2cd6d09334d4b00a2be4d532342b799b",
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Local,
  tmp_dir: "tmp",
  session_key_base: "9doqKjmNsklcWmv1+779E2su++ejdBhnSYgqAiGgwtAPpdVf4ns5eXi4IOZk1Eoi",
  session_signing_salt: "QftsNdJO",
  session_encryption_salt: "QftsNdJO",
  host: "localhost"

config :hexdocs, :repo_bucket, name: "staging.s3.hex.pm"

config :hexdocs, :docs_bucket, name: "hexdocs-private-staging"

config :goth,
  config: %{
    "type" => "service_account",
    "project_id" => "support",
    "token_source" => :oauth_jwt
  }
