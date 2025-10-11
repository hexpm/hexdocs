import gleam/dynamic/decode
import gleam/fetch
import gleam/hexpm
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise
import gleam/option
import gleam/result
import gleam/string
import gleam/uri
import hexdocs/endpoints
import hexdocs/loss
import hexdocs/services/hexdocs

pub fn package_versions(name: String) {
  let endpoint = endpoints.package(name)
  let assert Ok(request) = request.from_uri(endpoint)
  fetch.send(request)
  |> promise.try_await(fetch.read_json_body)
  |> promise.map(result.map_error(_, loss.FetchError))
  |> promise.map_try(fn(res) {
    decode.run(res.body, hexpm.package_decoder())
    |> result.map_error(loss.DecodeError)
    |> result.map(response.set_body(res, _))
  })
}

pub fn go_to_link(document: hexdocs.Document) {
  case string.split(document.package, on: "-") {
    [name, version, ..rest] -> {
      let version = string.join([version, ..rest], with: "-")
      ["https://hexdocs.pm", name, version, document.ref]
      |> string.join(with: "/")
      |> Ok
    }
    _ -> Error(Nil)
  }
}

pub fn preview_link(document: hexdocs.Document, theme: String) {
  let assert [name, vsn] = string.split(document.package, on: "-")
  ["https://hexdocs.pm", name, vsn, document.ref]
  |> string.join(with: "/")
  |> uri.parse
  |> result.map(fn(u) {
    uri.Uri(
      ..u,
      query: option.Some({
        uri.query_to_string([#("preview", "true"), #("theme", theme)])
      }),
    )
  })
  |> result.map(uri.to_string)
}
