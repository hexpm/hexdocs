import browser/document
import gleam/function
import gleam/http/response.{type Response}
import gleam/javascript/promise
import hexdocs/data/msg
import hexdocs/loss.{type Loss}
import hexdocs/services/hex
import hexdocs/services/hexdocs
import lustre/effect

pub fn packages() {
  use dispatch <- effect.from()
  use _ <- function.tap(Nil)
  use response <- promise.map(hexdocs.packages())
  let response = response_to_loss(response)
  dispatch(msg.ApiReturnedPackages(response))
}

pub fn package_versions(package: String) {
  use dispatch <- effect.from()
  use _ <- function.tap(Nil)
  use response <- promise.map(hex.package_versions(package))
  let response = response_to_loss(response)
  dispatch(msg.ApiReturnedPackageVersions(response:))
}

pub fn subscribe_blurred_search() {
  use dispatch <- effect.from()
  document.add_listener(fn() { dispatch(msg.UserBlurredSearch) })
  |> msg.DocumentRegisteredEventListener
  |> dispatch
}

pub fn typesense_search(query: String, packages: List(#(String, String))) {
  use dispatch <- effect.from()
  use _ <- function.tap(Nil)
  use response <- promise.map(hexdocs.typesense_search(query, packages, 1))
  let response = response_to_loss(response)
  dispatch(msg.ApiReturnedTypesenseSearch(response))
}

fn response_to_loss(response: Loss(Response(a))) -> Loss(a) {
  case response {
    Error(error) -> Error(error)
    Ok(response) if response.status == 200 -> Ok(response.body)
    Ok(_response) -> Error(loss.HttpError)
  }
}
