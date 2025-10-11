import gleam/bool
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import hexdocs/data/model.{type Model}
import hexdocs/data/model/autocomplete
import hexdocs/data/msg
import hexdocs/view/home/footer
import lustre/attribute.{class, id}
import lustre/element
import lustre/element/html
import lustre/event

pub fn home(model: Model) {
  // let go_back = event.on_click(msg.UserClickedGoBack)
  let toggle_mode = event.on_click(msg.UserToggledDarkMode)
  html.div([class("bg-white dark:bg-gray-900")], [
    html.div(
      [
        class("flex flex-col"),
        class("min-h-screen max-w-8xl"),
        class("mx-auto"),
        class("dark:text-gray-50"),
        class("transition-colors duration-200"),
        class("px-4 lg:px-0"),
      ],
      [
        html.main([class("flex-grow")], [
          html.section([class("sm:py-8 ly:py-10")], [
            html.div([id("nav"), class("flex justify-between items-center")], [
              html.a(
                [
                  attribute.href("#"),
                  class("text-sm text-gray-600 dark:text-gray-100 mt-10"),
                ],
                [html.text("← Go back to Hex")],
              ),
              html.button(
                [
                  toggle_mode,
                  class("p-3 text-gray-700 dark:text-gray-100 mt-10"),
                ],
                [html.i([class("theme-icon text-xl")], [])],
              ),
            ]),
            html.div([class("flex flex-col justify-around mt-14 lg:mt-40")], [
              html.div(
                [id("logo"), class("flex items-center justify-start gap-6")],
                [
                  html.img([
                    attribute.src("/images/hexdocs-logo.svg"),
                    attribute.alt("HexDocs Logo"),
                    class("w-auto h-14 lg:w-auto lg:h-24"),
                  ]),
                  html.h1(
                    [
                      class(
                        "text-gray-700 dark:text-gray-700 text-5xl lg:text-7xl font-(family-name:--font-calibri)",
                      ),
                    ],
                    [
                      html.span([class("font-semibold")], [html.text("hex")]),
                      html.span([class("font-light")], [html.text("docs")]),
                    ],
                  ),
                ],
              ),
              html.form(
                [
                  event.on_submit(fn(_) { msg.UserSubmittedSearch })
                    |> event.prevent_default
                    |> event.stop_propagation,
                  id("search"),
                  class(
                    "flex flex-col lg:flex-row items-center gap-4 mt-10 lg:mt-20",
                  ),
                ],
                [
                  html.div([class("relative max-w-lg w-full")], [
                    html.input([
                      attribute.value(model.home_input_displayed),
                      event.on_input(msg.UserEditedSearch),
                      event.on_click(msg.None) |> event.stop_propagation,
                      event.on_focus(msg.UserFocusedSearch),
                      event.advanced("keydown", on_arrow_up_down(model)),
                      attribute.autofocus(True),
                      attribute.type_("text"),
                      class("search-input w-full bg-white dark:bg-gray-800"),
                      class(
                        "rounded-lg border border-gray-200 dark:border-gray-700",
                      ),
                      class(
                        "font-(family-name:--font-inter) placeholder:text-gray-400 dark:placeholder:text-gray-400 text-gray-700 dark:text-gray-100",
                      ),
                      class("px-10 py-3"),
                      class(
                        "focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent",
                      ),
                      attribute.placeholder("Search for packages..."),
                    ]),
                    html.i(
                      [
                        class(
                          "ri-search-2-line absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 text-lg",
                        ),
                      ],
                      [],
                    ),
                    autocomplete(model),
                  ]),
                  html.button(
                    [
                      event.on("click", decode.failure(msg.None, ""))
                        |> event.stop_propagation,
                      class(
                        "px-6 py-3 bg-blue-600 dark:bg-blue-600 text-gray-50 font-(family-name:--font-inter) rounded-lg hover:bg-blue-700 transition duration-200 whitespace-nowrap w-full sm:w-auto",
                      ),
                    ],
                    [html.text("Search Packages")],
                  ),
                ],
              ),
              html.div([id("how-to"), class("mt-10 lg:mt-32")], [
                html.div([], [
                  html.h6(
                    [
                      class(
                        "text-gray-700 dark:text-gray-100 text-xl font-semibold font-(family-name:--font-inter) leading-loose",
                      ),
                    ],
                    [html.text("To search specific packages")],
                  ),
                  html.span(
                    [
                      class(
                        "text-gray-600 dark:text-gray-200 font-(family-name:--font-inter)",
                      ),
                    ],
                    [html.text("Type ")],
                  ),
                  html.span(
                    [class("bg-black px-0.5 text-gray-50 font-mono rounded")],
                    [html.text("#")],
                  ),
                  html.span(
                    [
                      class(
                        "text-gray-600 dark:text-gray-200 font-(family-name:--font-inter)",
                      ),
                    ],
                    [
                      html.text(
                        " to scope your search to one or more packages.",
                      ),
                      html.br([]),
                      html.text("Use "),
                    ],
                  ),
                  html.span(
                    [class("bg-black px-0.5 text-gray-50 font-mono rounded")],
                    [html.text("#<package>:<version>")],
                  ),
                  html.span(
                    [
                      class(
                        "text-gray-600 dark:text-gray-200 font-(family-name:--font-inter)",
                      ),
                    ],
                    [html.text(" to pick a specific version.")],
                  ),
                ]),
                html.div(
                  [attribute.class("font-(family-name:--font-inter) mt-10")],
                  [
                    html.h6(
                      [
                        attribute.class(
                          "text-gray-700 dark:text-gray-100 text-xl font-semibold leading-loose",
                        ),
                      ],
                      [
                        html.text(
                          "To access a package documentation
                                    ",
                        ),
                      ],
                    ),
                    html.span(
                      [attribute.class("text-gray-600 dark:text-gray-200")],
                      [html.text("Visit ")],
                    ),
                    html.span(
                      [
                        attribute.class(
                          "text-blue-600 dark:text-blue-600 font-semibold",
                        ),
                      ],
                      [html.text("hexdocs.pm/")],
                    ),
                    html.span(
                      [attribute.class("text-gray-600 dark:text-gray-200")],
                      [html.text("<package>")],
                    ),
                    html.span(
                      [attribute.class("text-gray-600 dark:text-gray-200")],
                      [html.text(" or ")],
                    ),
                    html.span(
                      [
                        attribute.class(
                          "text-blue-600 dark:text-blue-600 font-semibold",
                        ),
                      ],
                      [html.text("hexdocs.pm/")],
                    ),
                    html.span(
                      [attribute.class("text-gray-600 dark:text-gray-200")],
                      [html.text("<package>/<version>")],
                    ),
                  ],
                ),
              ]),
            ]),
          ]),
        ]),
        footer.footer(),
      ],
    ),
  ])
}

fn on_arrow_up_down(model: Model) {
  use key <- decode.field("key", decode.string)
  let message = case key, model.autocomplete {
    "ArrowDown", _ -> Ok(msg.UserSelectedNextAutocompletePackage)
    "ArrowUp", _ -> Ok(msg.UserSelectedPreviousAutocompletePackage)
    "Tab", Some(_) -> Ok(msg.UserSubmittedAutocomplete)
    // Error case, giving anything to please the decode failure.
    _, _ -> Error(msg.None)
  }
  case message {
    Ok(msg) ->
      event.handler(msg, stop_propagation: False, prevent_default: True)
    Error(msg) ->
      event.handler(msg, stop_propagation: False, prevent_default: False)
  }
  |> decode.success
}

fn autocomplete(model: Model) {
  let no_search = string.is_empty(model.home_input)
  let no_autocomplete = option.is_none(model.autocomplete)
  use <- bool.lazy_guard(
    when: model.autocomplete_search_focused != model.AutocompleteOnHome,
    return: element.none,
  )
  use <- bool.lazy_guard(when: no_search, return: element.none)
  use <- bool.lazy_guard(when: no_autocomplete, return: element.none)
  html.div(
    [
      class(
        "absolute top-14 w-full bg-white dark:bg-gray-800 shadow-md rounded-lg overflow-hidden",
      ),
    ],
    [
      case model.autocomplete {
        None -> element.none()
        Some(#(type_, autocomplete)) -> {
          let items = autocomplete.all(autocomplete)
          case list.is_empty(items), type_ {
            True, model.Package -> empty_package_autocomplete()
            True, model.Version -> empty_versions_autocomplete()
            False, _ -> {
              html.div([], {
                use package <- list.map(items)
                let is_selected =
                  autocomplete.is_selected(autocomplete, package)
                let selected = case is_selected {
                  True -> class("bg-stone-100 dark:bg-stone-600")
                  False -> attribute.none()
                }
                let on_click = on_select_package(package)
                html.div(
                  [
                    class(
                      "py-2 px-4 text-md hover:bg-stone-200 dark:hover:bg-stone-800 cursor-pointer",
                    ),
                    selected,
                    on_click,
                  ],
                  [html.text(package)],
                )
              })
            }
          }
        }
      },
    ],
  )
}

fn empty_package_autocomplete() {
  html.text("No packages found")
}

fn empty_versions_autocomplete() {
  html.text("No versions found")
}

fn on_select_package(package: String) {
  msg.UserClickedAutocompletePackage(package)
  |> event.on_click
  |> event.stop_propagation
}
