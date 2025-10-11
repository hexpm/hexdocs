import gleam/bool
import gleam/dynamic/decode
import gleam/fetch
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import hexdocs/endpoints
import hexdocs/environment
import hexdocs/loss

pub type TypeSense {
  TypeSense(document: Document, highlight: Highlights)
}

pub type Document {
  Document(
    doc: String,
    id: String,
    package: String,
    proglang: String,
    ref: String,
    title: String,
    type_: String,
  )
}

pub type Highlights {
  Highlights(doc: Option(Highlight), title: Option(Highlight))
}

pub type Highlight {
  Highlight(matched_tokens: List(String), snippet: String)
}

pub fn packages() {
  case environment.read() {
    environment.Development | environment.Staging | environment.Production -> {
      let endpoint = endpoints.packages()
      let assert Ok(request) = request.from_uri(endpoint)
      fetch.send(request)
      |> promise.try_await(fetch.read_text_body)
      |> promise.map(result.map_error(_, loss.FetchError))
    }
  }
}

pub fn typesense_search(
  query: String,
  packages: List(#(String, String)),
  page: Int,
) {
  let query = new_search_query_params(query, packages, page)
  let endpoint = uri.Uri(..endpoints.search(), query: Some(query))
  let assert Ok(request) = request.from_uri(endpoint)
  fetch.send(request)
  |> promise.try_await(fetch.read_json_body)
  |> promise.map(result.map_error(_, loss.FetchError))
}

pub fn typesense_decoder() {
  use found <- decode.field("found", decode.int)
  use hits <- decode.field("hits", {
    decode.list({
      use document <- decode.field("document", {
        use doc <- decode.field("doc", decode.string)
        use id <- decode.field("id", decode.string)
        use package <- decode.field("package", decode.string)
        use proglang <- decode.field("proglang", decode.string)
        use ref <- decode.field("ref", decode.string)
        use title <- decode.field("title", decode.string)
        use type_ <- decode.field("type", decode.string)
        Document(doc:, id:, package:, proglang:, ref:, title:, type_:)
        |> decode.success
      })
      use highlight <- decode.field("highlight", {
        let highlight = highlight_decoder() |> decode.map(Some)
        use doc <- decode.optional_field("doc", None, highlight)
        use title <- decode.optional_field("title", None, highlight)
        decode.success(Highlights(doc:, title:))
      })
      decode.success(TypeSense(document:, highlight:))
    })
  })
  decode.success(#(found, hits))
}

fn new_search_query_params(
  query: String,
  packages: List(#(String, String)),
  page: Int,
) {
  list.new()
  |> list.key_set("q", query)
  |> list.key_set("query_by", "title,doc")
  |> list.key_set("page", int.to_string(page))
  |> add_filter_by_packages_param(packages)
  |> uri.query_to_string
}

fn add_filter_by_packages_param(
  query: List(#(String, String)),
  packages: List(#(String, String)),
) -> List(#(String, String)) {
  use <- bool.guard(when: list.is_empty(packages), return: query)
  packages
  |> list.map(fn(p) { p.0 <> "-" <> p.1 })
  |> list.map(string.append("package:=", _))
  |> string.join("||")
  |> list.key_set(query, "filter_by", _)
}

fn highlight_decoder() {
  let matched_tokens = decode.list(decode.string)
  use matched_tokens <- decode.field("matched_tokens", matched_tokens)
  use snippet <- decode.field("snippet", decode.string)
  Highlight(matched_tokens:, snippet:)
  |> decode.success
}
