import Config

config :hexdocs,
  port: "5002",
  hexpm_url: "http://localhost:5000",
  hexpm_impl: Hexdocs.HexpmMock,
  store_impl: Hexdocs.Store.Local,
  cdn_impl: Hexdocs.CDN.Local,
  search_impl: Hexdocs.Search.Local,
  source_repo_impl: Hexdocs.SourceRepo.Mock

config :logger, level: :warning
