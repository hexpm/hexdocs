import Config

config :hexdocs,
  hexpm_url: "http://localhost:5000",
  hexpm_impl: Hexdocs.HexpmMock,
  store_impl: Hexdocs.Store.Local,
  cdn_impl: Hexdocs.CDN.Local,
  search_impl: Hexdocs.Search.Local,
  source_repo_impl: Hexdocs.SourceRepo.Mock,
  hex_repo_impl: Hexdocs.HexRepo.Mock,
  private_host: "localhost"

config :logger, level: :warning
