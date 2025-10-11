import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import hexdocs/components/iframe
import hexdocs/data/model.{type Model}
import hexdocs/data/model/autocomplete
import hexdocs/data/msg
import hexdocs/services/hex
import hexdocs/services/hexdocs
import lustre/attribute.{class}
import lustre/element
import lustre/element/html
import lustre/event

pub fn search(model: Model) {
  element.fragment([
    html.div(
      [
        class(
          "fixed top-[22px] right-4 z-50 flex-col items-end gap-4 hidden 2xl:flex",
        ),
      ],
      [hexdocs_logo()],
    ),
    html.div([class("flex flex-col md:flex-row")], [
      html.div(
        [
          class(
            "md:hidden flex items-center justify-between p-4 bg-slate-100 dark:bg-slate-800",
          ),
        ],
        [
          html.button(
            [
              class("p-2"),
              event.on_click(msg.UserToggledSidebar),
            ],
            [
              html.i(
                [
                  class(
                    "ri-menu-line text-xl text-slate-700 dark:text-slate-300",
                  ),
                ],
                [],
              ),
            ],
          ),
          hexdocs_logo(),
          html.button([class("p-2"), event.on_click(msg.UserToggledDarkMode)], [
            html.i(
              [
                class("theme-icon text-xl text-slate-700 dark:text-slate-300"),
                class(case model.dark_mode.mode {
                  msg.Dark -> "ri-sun-line"
                  msg.Light -> "ri-moon-line"
                }),
              ],
              [],
            ),
          ]),
        ],
      ),
      html.div(
        [
          class(
            "w-80 h-screen bg-slate-100 dark:bg-slate-800 fixed md:static z-40 -translate-x-full md:translate-x-0 transition-transform duration-300 ease-in-out top-0",
          ),
          class(case model.sidebar_opened {
            True -> "translate-x-0"
            False -> "-translate-x-full"
          }),
          event.on_click(msg.None) |> event.stop_propagation,
          attribute.id("sidebar"),
        ],
        [
          html.div([class("p-5")], [
            html.div([class("flex justify-between items-center mt-2")], [
              html.h2(
                [
                  class(
                    "text-slate-950 dark:text-slate-50 text-lg font-medium leading-7",
                  ),
                ],
                [html.text("Selected Packages")],
              ),
              html.button(
                [
                  class("md:hidden p-2"),
                  event.on_click(msg.UserToggledSidebar),
                ],
                [
                  html.i(
                    [
                      class(
                        "ri-close-line text-xl text-slate-700 dark:text-slate-300",
                      ),
                    ],
                    [],
                  ),
                ],
              ),
            ]),
            html.form(
              [event.on_submit(fn(_) { msg.UserSubmittedPackagesFilter })],
              [
                html.div([class("mt-4 flex gap-2")], [
                  html.div(
                    [
                      class(
                        "flex-grow bg-slate-100 dark:bg-slate-700 rounded-lg border border-slate-300 dark:border-slate-600 relative",
                      ),
                    ],
                    [
                      html.input([
                        attribute.id("search-package-input"),
                        class(
                          "search-input w-full h-10 bg-transparent px-10 text-slate-800 dark:text-slate-200 text-sm focus:outline-none focus:ring-1 focus:ring-blue-500",
                        ),
                        attribute.placeholder("Package Name"),
                        attribute.type_("text"),
                        attribute.value(
                          model.search_packages_filter_input_displayed,
                        ),
                        event.on_input(msg.UserEditedPackagesFilterInput),
                        event.on_focus(msg.UserFocusedPackagesFilterInput),
                        event.on_click(msg.None) |> event.stop_propagation,
                        event.advanced(
                          "keydown",
                          on_arrow_up_down(model.Package),
                        ),
                      ]),
                      html.i(
                        [
                          class(
                            "ri-search-2-line absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-500 dark:text-slate-400 text-lg",
                          ),
                        ],
                        [],
                      ),
                      autocomplete(
                        model,
                        model.Package,
                        model.AutocompleteOnPackage,
                      ),
                    ],
                  ),
                  html.div(
                    [
                      class(
                        "w-20 bg-slate-100 dark:bg-slate-700 rounded-lg border border-slate-300 dark:border-slate-600 relative",
                      ),
                    ],
                    [
                      html.input([
                        attribute.id("search-version-input"),
                        class(
                          "search-input w-full h-10 bg-transparent px-2 text-slate-800 dark:text-slate-200 text-sm focus:outline-none focus:ring-1 focus:ring-blue-500 disabled:opacity-[0.2]",
                        ),
                        attribute.placeholder("ver"),
                        attribute.type_("text"),
                        attribute.value(
                          model.search_packages_filter_version_input_displayed,
                        ),
                        attribute.disabled(
                          !list.contains(
                            model.packages,
                            model.search_packages_filter_input_displayed,
                          ),
                        ),
                        event.on_input(msg.UserEditedPackagesFilterVersion),
                        event.on_focus(msg.UserFocusedPackagesFilterVersion),
                        event.on_click(msg.None) |> event.stop_propagation,
                        event.advanced(
                          "keydown",
                          on_arrow_up_down(model.Version),
                        ),
                      ]),
                      autocomplete(
                        model,
                        model.Version,
                        model.AutocompleteOnVersion,
                      ),
                    ],
                  ),
                ]),
                html.div([class("mt-4 flex gap-2")], [
                  html.button(
                    [
                      attribute.type_("submit"),
                      class(
                        "flex-grow bg-blue-600 hover:bg-blue-700 text-slate-100 rounded-lg h-10 flex items-center justify-center transition duration-200",
                      ),
                    ],
                    [
                      html.span([class("text-sm font-medium")], [
                        html.text("+ Add Package"),
                      ]),
                    ],
                  ),
                  html.button(
                    [
                      event.on_click(msg.UserClickedShare),
                      class(
                        "w-10 h-10 bg-slate-100 dark:bg-slate-700 rounded-lg border border-slate-300 dark:border-slate-600 flex items-center justify-center cursor-pointer",
                      ),
                    ],
                    [
                      html.i(
                        [
                          class(
                            "ri-share-forward-line text-slate-500 dark:text-slate-400 text-lg",
                          ),
                        ],
                        [],
                      ),
                    ],
                  ),
                ]),
              ],
            ),
            html.hr([class("mt-6 border-slate-200 dark:border-slate-700")]),
            case list.is_empty(model.search_packages_filters) {
              True -> {
                html.div([class("text-slate-950 dark:text-slate-50 pt-4")], [
                  html.text("No package selected, searching all packages"),
                ])
              }
              False -> {
                element.fragment({
                  use filter <- list.map(model.search_packages_filters)
                  let #(package, version) = filter
                  html.div([class("flex justify-between items-center mt-4")], [
                    html.div(
                      [class("inline-flex flex-col justify-start items-start")],
                      [
                        html.div(
                          [
                            class(
                              "self-stretch justify-start text-gray-950 dark:text-slate-50 text-lg font-semibold leading-none",
                            ),
                          ],
                          [html.text(package)],
                        ),
                        html.div(
                          [
                            class(
                              "self-stretch justify-start text-slate-700 dark:text-slate-400 text-sm font-normal leading-none",
                            ),
                          ],
                          [html.text(version)],
                        ),
                      ],
                    ),
                    trash_button(filter),
                  ])
                })
              }
            },
          ]),
        ],
      ),
      html.div([class("flex-1 md:ml-0 mt-0 md:mt-0")], [
        html.div([class("p-5 flex flex-col items-center")], [
          html.div([class("w-full max-w-[800px] flex items-center gap-3")], [
            html.div([class("relative flex-1")], [
              html.input([
                attribute.value(model.search_input),
                event.on_input(msg.UserEditedSearchInput),
                event.on("keydown", {
                  use key <- decode.field("key", decode.string)
                  case key {
                    "Enter" -> decode.success(msg.UserSubmittedSearchInput)
                    _ -> decode.failure(msg.UserSubmittedSearchInput, "Key")
                  }
                }),
                attribute.placeholder("Search for packages..."),
                class(
                  "search-input w-full h-10 bg-indigo-50 dark:bg-slate-800 rounded-lg border border-blue-500 dark:border-blue-600 pl-10 pr-4 text-slate-950 dark:text-slate-50 focus:outline-none focus:ring-1 focus:ring-blue-500",
                ),
                attribute.type_("text"),
              ]),
              html.i(
                [
                  class(
                    "ri-search-2-line absolute left-4 top-1/2 transform -translate-y-1/2 text-slate-950 dark:text-slate-400",
                  ),
                ],
                [],
              ),
            ]),
            // html.i(
            //   [
            //     class(
            //       "ri-settings-4-line text-xl text-slate-700 dark:text-slate-300",
            //     ),
            //   ],
            //   [],
            // ),
            html.button(
              [class("p-2"), event.on_click(msg.UserToggledDarkMode)],
              [
                html.i(
                  [
                    class(
                      "theme-icon text-xl text-slate-700 dark:text-slate-300",
                    ),
                    class(case model.dark_mode.mode {
                      msg.Dark -> "ri-sun-line"
                      msg.Light -> "ri-moon-line"
                    }),
                  ],
                  [],
                ),
              ],
            ),
          ]),
        ]),
        html.div([class("px-5 flex flex-col items-center")], [
          html.div([class("space-y-6 w-full max-w-[800px]")], {
            let results = option.unwrap(model.search_result, #(0, []))
            use result <- list.map(results.1)
            result_card(model, result)
          }),
        ]),
      ]),
    ]),
  ])
}

fn on_arrow_up_down(type_: model.Type) {
  use key <- decode.field("key", decode.string)
  let message = case key, type_ {
    "ArrowDown", _ -> Ok(msg.UserSelectedNextAutocompletePackage)
    "ArrowUp", _ -> Ok(msg.UserSelectedPreviousAutocompletePackage)
    "Enter", model.Package -> Ok(msg.UserSelectedPackageFilter)
    "Enter", model.Version -> Ok(msg.UserSelectedPackageFilterVersion)
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

fn autocomplete(
  model: Model,
  type_: model.Type,
  opened: model.AutocompleteFocused,
) -> element.Element(msg.Msg) {
  let no_search = case type_ {
    model.Package -> string.is_empty(model.search_packages_filter_input)
    model.Version -> False
  }
  let no_autocomplete = option.is_none(model.autocomplete)
  use <- bool.lazy_guard(
    when: model.autocomplete_search_focused != opened,
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
        Some(#(_type_, autocomplete)) -> {
          let items = autocomplete.all(autocomplete)
          let is_empty = list.is_empty(items)
          use <- bool.lazy_guard(when: is_empty, return: empty_autocomplete)
          html.div([], {
            use package <- list.map(items)
            let is_selected = autocomplete.is_selected(autocomplete, package)
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
      },
    ],
  )
}

fn empty_autocomplete() {
  html.text("No packages found")
}

fn on_select_package(package: String) {
  msg.UserClickedAutocompletePackage(package)
  |> event.on_click
  |> event.stop_propagation
}

fn hexdocs_logo() {
  html.a([class("flex items-center gap-2"), attribute.href("/")], [
    html.img([
      class("w-auto h-10"),
      attribute.alt("HexDocs Logo"),
      attribute.src("/images/hexdocs-logo.svg"),
    ]),
    html.div([class("flex items-center")], [
      html.span(
        [
          class(
            "text-slate-950 text-lg font-bold font-(family-name:--font-calibri)",
          ),
        ],
        [html.text("hex")],
      ),
      html.span(
        [
          class("text-slate-950 text-lg font-(family-name:--font-calibri)"),
        ],
        [html.text("docs")],
      ),
    ]),
  ])
}

fn trash_button(filter: #(String, String)) {
  let on_delete = event.on_click(msg.UserDeletedPackagesFilter(filter))
  html.div(
    [class("w-5 h-5 relative overflow-hidden cursor-pointer"), on_delete],
    [
      sidebar_icon("ri-delete-bin-5-fill"),
    ],
  )
}

fn result_card(model: Model, result: hexdocs.TypeSense) {
  html.div([class("w-full bg-slate-100 dark:bg-slate-800 rounded-2xl p-4")], [
    html.div([class("text-slate-700 dark:text-slate-300 text-sm")], [
      html.text(result.document.package),
    ]),
    html.h3(
      [
        class(
          "text-slate-950 dark:text-slate-50 text-xl font-semibold leading-loose mt-1",
        ),
      ],
      [html.text(result.document.title)],
    ),
    // element.unsafe_raw_html(
    //   "",
    //   "p",
    //   [
    //     class(
    //       "mt-4 text-slate-800 dark:text-slate-300 leading-normal line-clamp-2 overflow-hidden",
    //     ),
    //   ],
    //   result.document.doc,
    // ),
    html.div(
      [
        class(
          "mt-2 inline-flex px-3 py-0.5 bg-slate-300 dark:bg-slate-700 rounded-full",
        ),
      ],
      [
        html.span([class("text-blue-600 dark:text-blue-400 text-sm")], [
          html.text(result.document.ref),
        ]),
      ],
    ),
    case result.highlight {
      hexdocs.Highlights(doc: Some(doc), ..) -> {
        element.unsafe_raw_html(
          "",
          "p",
          [
            class(
              "mt-4 text-slate-800 dark:text-slate-300 leading-normal line-clamp-2 overflow-hidden",
            ),
          ],
          doc.snippet,
        )
        // html.text("Channels are a really good abstraction"),
        // html.span(
        //   [class("bg-slate-950 text-slate-100 px-1 rounded")],
        //   [html.text("for")],
        // ),
        // html.text(
        //   "real-time communication. They are bi-directional and persistent connections between the browser and server...",
        // )
      }
      _ -> element.none()
    },
    html.div([class("mt-4 flex flex-wrap gap-3")], [
      html.button(
        [
          event.on_click(msg.UserToggledPreview(result.document.id)),
          class(
            "h-10 px-4 py-2.5 bg-slate-100 dark:bg-slate-700 rounded-lg border border-slate-300 dark:border-slate-600 flex items-center justify-center",
          ),
        ],
        [
          html.span(
            [class("text-slate-800 dark:text-slate-200 text-sm font-semibold")],
            [html.text("Show Preview")],
          ),
          card_icon("ri-arrow-down-s-line"),
        ],
      ),
      case hex.go_to_link(result.document) {
        Error(_) -> element.none()
        Ok(link) ->
          html.a(
            [
              attribute.href(link),
              class(
                "h-10 px-4 py-2.5 bg-slate-100 dark:bg-slate-700 rounded-lg border border-slate-300 dark:border-slate-600 flex items-center justify-center",
              ),
            ],
            [
              html.span(
                [
                  class(
                    "text-slate-800 dark:text-slate-200 text-sm font-semibold",
                  ),
                ],
                [html.text("Go to Page")],
              ),
              card_icon("ri-external-link-line"),
            ],
          )
      },
    ]),
    case dict.get(model.search_opened_previews, result.document.id) {
      Ok(False) | Error(_) -> element.none()
      Ok(True) -> {
        case
          hex.preview_link(result.document, case model.dark_mode.mode {
            msg.Dark -> "dark"
            msg.Light -> "light"
          })
        {
          Error(_) -> element.none()
          Ok(link) -> {
            html.div([class("h-100 pt-4")], [
              iframe.iframe([
                class("rounded-lg shadow-sm"),
                iframe.to(link),
                iframe.title(result.document.package),
              ]),
            ])
          }
        }
      }
    },
  ])
}

fn sidebar_icon(icon: String) {
  let icon = class(icon)
  let default = class("text-slate-400 dark:text-slate-500")
  html.i([icon, default], [])
}

fn card_icon(icon: String) {
  let icon = class(icon)
  let default = class("ml-2 text-slate-500 dark:text-slate-400")
  html.i([icon, default], [])
}
