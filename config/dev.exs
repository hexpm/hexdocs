import Config

config :hexdocs,
  port: "4002",
  hexpm_url: "http://localhost:4000",
  hexpm_impl: Hexdocs.Hexpm.Impl,
  store_impl: Hexdocs.Store.Local,
  cdn_impl: Hexdocs.CDN.Local
