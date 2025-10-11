import gleam/uri.{type Uri}

const search_url = "https://search.hexdocs.pm"

const hexdocs_url = "https://hexdocs.pm"

const hexpm_url = "https://hex.pm"

pub fn search() -> Uri {
  let assert Ok(uri) = uri.parse(search_url)
  uri
}

pub fn packages() -> Uri {
  let assert Ok(uri) = uri.parse(hexdocs_url <> "/package_names.csv")
  uri
}

pub fn package(package: String) -> Uri {
  let assert Ok(uri) = uri.parse(hexpm_url <> "/api/packages/" <> package)
  uri
}
