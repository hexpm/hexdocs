import browser/document
import gleam/bool
import gleam/dict.{type Dict}
import gleam/function
import gleam/hexpm
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/uri
import hexdocs/data/model/autocomplete.{type Autocomplete}
import hexdocs/data/model/route.{type Route}
import hexdocs/data/model/version
import hexdocs/data/msg.{type Msg}
import hexdocs/effects
import hexdocs/loss
import hexdocs/services/hex
import hexdocs/services/hexdocs
import lustre/effect.{type Effect}

pub type Model {
  Model(
    /// Current route of the application. Mapping `window.location` <=> `Route`.
    route: Route,
    /// When focusing the autocomplete, clicking on the DOM should close it.
    /// To listen to such event, an event listener on the `document` should be
    /// setup. It should be cleaned atferwards, if the user closed the
    /// autocomplete while not clicking on the DOM (for example, because the
    /// user accepted a proposition). `dom_click_unsubscriber` stores the
    /// function to revoke the event listener.
    dom_click_unsubscriber: Option(fn() -> Nil),
    dark_mode: msg.ColorSetting,
    /// Stores the content of the `https://hexdocs.pm/package_names.csv`.
    packages: List(String),
    /// Stores the different versions of a package.
    /// `Dict(Package Name, hexpm.Package)`.
    packages_versions: Dict(String, hexpm.Package),
    /// Stores the open state of the sidebar.
    sidebar_opened: Bool,
    dom_click_sidebar_unsubscriber: Option(fn() -> Nil),
    /// Stores the content of the search input on the home page, entered
    /// by the user.
    home_input: String,
    /// Stores the current displayed content of the search input on the home
    /// page. Differs from `home_input` as, like on Google Search, hovering on
    /// the autocomplete will update the displayed value in the input, to let
    /// the user to continue typing after selecting an item. \
    /// For instance, a user could type `#lus`, select `lustre` in the
    /// autocomplete, the input will display `#lustre`, and the user can then
    /// type `:`. The input will be `#lustre:`, and it will trigger the
    /// autocomplete package versions.
    home_input_displayed: String,
    /// Stores the current state of the autocomplete. The autocomplete can be
    /// triggered for packages and version numbers.
    autocomplete: Option(#(Type, Autocomplete)),
    /// Whether the autocomplete is focused, or not.
    autocomplete_search_focused: AutocompleteFocused,
    /// Keeps the results from TypeSense.
    /// `#(Page, List(Results))`.
    search_result: Option(#(Int, List(hexdocs.TypeSense))),
    /// Stores the current value of the search bar on top of the search page.
    search_input: String,
    /// Stores the current state of the different previews opened in
    /// the search results, in the search page. An item missing from the
    /// `Dict` indicates a preview _not_ openend.
    search_opened_previews: Dict(String, Bool),
    /// Stores the current value of the packages filter input on
    /// left of the search page.
    search_packages_filter_input: String,
    search_packages_filter_input_displayed: String,
    /// Stores the current value of the packages version input on
    /// left of the search page.
    search_packages_filter_version_input: String,
    search_packages_filter_version_input_displayed: String,
    /// Store the current set packages filters.
    search_packages_filters: List(#(String, String)),
  )
}

pub type AutocompleteFocused {
  AutocompleteClosed
  AutocompleteOnHome
  AutocompleteOnPackage
  AutocompleteOnVersion
}

/// Autocomplete can be used with Package or Version.
pub type Type {
  Package
  Version
}

pub fn new(dark_mode: msg.ColorSetting) -> Model {
  Model(
    route: route.Home,
    dom_click_unsubscriber: None,
    dark_mode:,
    packages: [],
    packages_versions: dict.new(),
    sidebar_opened: False,
    dom_click_sidebar_unsubscriber: None,
    home_input: "",
    home_input_displayed: "",
    autocomplete: None,
    autocomplete_search_focused: AutocompleteClosed,
    search_result: None,
    search_input: "",
    search_opened_previews: dict.new(),
    search_packages_filter_input: "",
    search_packages_filter_input_displayed: "",
    search_packages_filter_version_input: "",
    search_packages_filter_version_input_displayed: "",
    search_packages_filters: [],
  )
}

/// Add packages in the `Model`, allowing them to be easily parsed, used in
/// autocomplete, etc. The `Model` acts as a cache for the packages list,
/// fetched at every application startup.
pub fn add_packages(model: Model, packages: List(String)) -> Model {
  let packages = list.filter(packages, fn(p) { p != "" })
  Model(..model, packages:)
}

pub fn add_packages_versions(
  model: Model,
  packages: List(hexpm.Package),
) -> Model {
  use model, package <- list.fold(packages, model)
  Model(..model, packages_versions: {
    dict.insert(model.packages_versions, package.name, package)
  })
}

pub fn toggle_sidebar(model: Model) {
  let model = Model(..model, sidebar_opened: !model.sidebar_opened)
  let unsub = unsubscribe_sidebar_dom_click(model)
  case model.sidebar_opened {
    False -> #(Model(..model, dom_click_sidebar_unsubscriber: None), unsub)
    True -> #(
      Model(..model, dom_click_sidebar_unsubscriber: None),
      effect.batch([unsub, subscribe_sidebar_dom_click()]),
    )
  }
}

fn unsubscribe_sidebar_dom_click(model: Model) {
  use _ <- effect.from()
  let unsub = model.dom_click_sidebar_unsubscriber
  let unsub = option.unwrap(unsub, fn() { Nil })
  unsub()
}

fn subscribe_sidebar_dom_click() {
  use dispatch, _ <- effect.after_paint()
  document.add_listener(fn() { dispatch(msg.UserClosedSidebar) })
  |> msg.DocumentRegisteredSidebarListener
  |> dispatch
}

pub fn close_sidebar(model: Model) {
  Model(..model, dom_click_sidebar_unsubscriber: None, sidebar_opened: False)
  |> pair.new(effect.none())
}

/// Updates the color theme according to `(prefers-color-scheme)` of the
/// browser. If user setup setting by hand, the change _will not_ have any
/// effect.
pub fn update_color_theme(model: Model, color_theme: msg.ColorMode) {
  case model.dark_mode {
    msg.System(_) -> Model(..model, dark_mode: msg.System(color_theme))
    msg.User(_) -> model
  }
}

/// Toggle the dark theme as asked by the user. By design, when the user
/// overrides the system setting, the theme will now only be controlled by the
/// user, and `(prefers-color-scheme: dark)` will have no effect on the color
/// mode of the application.
pub fn toggle_dark_theme(model: Model) {
  Model(..model, dark_mode: {
    msg.User({
      case model.dark_mode.mode {
        msg.Dark -> msg.Light
        msg.Light -> msg.Dark
      }
    })
  })
}

pub fn update_home_search(model: Model, home_input: String) {
  Model(..model, home_input:, home_input_displayed: home_input)
  |> autocomplete_packages(home_input)
  |> autocomplete_versions(home_input)
}

pub fn focus_home_search(model: Model) {
  Model(..model, autocomplete_search_focused: {
    case model.autocomplete_search_focused, model.route {
      AutocompleteClosed, route.Home -> AutocompleteOnHome
      state, _ -> state
    }
  })
  |> autocomplete_packages(model.home_input)
  |> autocomplete_versions(model.home_input)
}

pub fn focus_packages_filter_search(model: Model) {
  Model(..model, autocomplete_search_focused: AutocompleteOnPackage)
  |> autocomplete_packages(model.search_packages_filter_input)
}

pub fn focus_packages_filter_version_search(model: Model) {
  Model(..model, autocomplete_search_focused: AutocompleteOnVersion)
  |> autocomplete_versions(model.search_packages_filter_version_input_displayed)
}

pub fn update_route(model: Model, route: uri.Uri) {
  let route = route.from_uri(route)
  let model =
    Model(
      ..model,
      route:,
      search_packages_filter_version_input: "",
      search_packages_filter_version_input_displayed: "",
      search_packages_filter_input: "",
      search_packages_filter_input_displayed: "",
    )
  case route {
    route.Home | route.NotFound -> #(model, effect.none())
    route.Search(q:, packages:) -> {
      Model(..model, search_input: q, search_packages_filters: packages)
      |> pair.new(effects.typesense_search(q, packages))
    }
  }
}

pub fn select_autocomplete_option(model: Model, package: String) {
  case model.autocomplete, model.route {
    None, _ -> model
    Some(_), route.NotFound -> model
    Some(#(type_, _autocomplete)), route.Home -> {
      let home_input_displayed =
        replace_last_word(model.home_input_displayed, package, type_)
      Model(
        ..model,
        home_input: home_input_displayed,
        home_input_displayed:,
        autocomplete: None,
      )
    }
    Some(#(type_, _autocomplete)), route.Search(..) -> {
      let model = Model(..model, autocomplete: None)
      case type_ {
        Package -> {
          model.packages
          |> list.find(fn(p) { p == package })
          |> result.map(fn(_) {
            Model(
              ..model,
              search_packages_filter_input: package,
              search_packages_filter_input_displayed: package,
            )
          })
          |> result.unwrap(model)
        }
        Version -> {
          let version = package
          let package = model.search_packages_filter_input_displayed
          model.packages_versions
          |> dict.get(package)
          |> result.map(fn(package) { package.releases })
          |> result.try(list.find(_, fn(r) { r.version == version }))
          |> result.map(fn(_) {
            Model(
              ..model,
              search_packages_filter_version_input: version,
              search_packages_filter_version_input_displayed: version,
            )
          })
          |> result.unwrap(model)
        }
      }
    }
  }
}

/// When going from the home page, where you have a free text input to the
/// search page, it's needed to keep the different parts of the search, while
/// changing how they're handled in the model. That function transforms the
/// simple text input in the advanced filters parts in the Model.
pub fn compute_filters_input(model: Model) -> #(Model, Effect(Msg)) {
  let #(filters, packages_to_fetch) = extract_packages_filters_or_fetches(model)
  let search_input = keep_search_input_non_packages_text(model)
  case list.is_empty(packages_to_fetch) {
    True -> {
      #(Model(..model, search_packages_filters: filters, search_input:), {
        route.push(route.Search(q: search_input, packages: filters))
      })
    }
    False -> #(model, {
      use dispatch <- effect.from()
      use _ <- function.tap(Nil)
      packages_to_fetch
      |> list.map(fn(package) { hex.package_versions(package) })
      |> promise.await_list
      |> promise.map(fn(packages) {
        use response <- list.try_map(packages)
        use response <- result.try(response)
        let is_valid = response.status == 200
        use <- bool.guard(when: !is_valid, return: Error(loss.HttpError))
        Ok(response.body)
      })
      |> promise.map(fn(packages) {
        dispatch(msg.ApiReturnedPackagesVersions(packages))
      })
    })
  }
}

/// Typical home search input will be something like `foo #phoenix #ecto:1.0.0`.
/// `extract_packages_filters_or_fetches` will extract the `#ecto:1.0.0` part
/// as a filter, and will return a side-effect to fetch `phoenix`, in order to
/// always query the latest version. When all packages have been fetched and are
/// stored in the model, `extract_packages_filters_or_fetches` will return the
/// correct model and will reroute to the search page.
fn extract_packages_filters_or_fetches(model: Model) {
  let segments = string.split(model.home_input_displayed, on: " ")
  let search_packages_filters = list.filter_map(segments, version.match_package)
  list.fold(search_packages_filters, #([], []), fn(acc, val) {
    let #(filters, packages_to_fetch) = acc
    let #(package, version) = val
    let is_existing_package = list.contains(model.packages, package)
    use <- bool.guard(when: !is_existing_package, return: acc)
    case version {
      Some(version) -> #([#(package, version), ..filters], packages_to_fetch)
      None -> {
        case dict.get(model.packages_versions, package) {
          Error(_) -> #(filters, [package, ..packages_to_fetch])
          Ok(versionned) -> {
            case list.first(versionned.releases) {
              // That case is impossible, returning the neutral element.
              Error(_) -> #(filters, packages_to_fetch)
              Ok(release) -> {
                let version = release.version
                #([#(package, version), ..filters], packages_to_fetch)
              }
            }
          }
        }
      }
    }
  })
}

/// Typical home search input will be something like `foo #phoenix #ecto:1.0.0`.
/// `keep_search_input_non_packages_text` keeps only the `foo` part of the
/// search input.
fn keep_search_input_non_packages_text(model: Model) -> String {
  let segments = string.split(model.home_input_displayed, on: " ")
  segments
  |> list.filter(fn(s) { version.match_package(s) |> result.is_error })
  |> string.join(with: " ")
}

/// When typing to select a new package filter on the search page, if the
/// package is incomplete when submitting, the autocomplete will automatically
/// takes the first package in the list.
pub fn get_selected_package_filter_name(model: Model) {
  let is_valid =
    list.contains(model.packages, model.search_packages_filter_input_displayed)
  case is_valid, model.autocomplete {
    True, _ -> Ok(model.search_packages_filter_input_displayed)
    False, None -> Error(Nil)
    False, Some(#(_, autocomplete)) -> {
      autocomplete.all(autocomplete)
      |> list.first
    }
  }
}

pub fn set_search_results(
  model: Model,
  search_result: #(Int, List(hexdocs.TypeSense)),
) -> Model {
  let search_result = Some(search_result)
  Model(..model, search_result:)
}

pub fn blur_search(model: Model) {
  Model(
    ..model,
    autocomplete_search_focused: AutocompleteClosed,
    autocomplete: None,
    home_input: model.home_input_displayed,
    dom_click_unsubscriber: None,
  )
  |> pair.new({ unsubscribe_dom_listener(model) })
}

pub fn unsubscribe_dom_listener(model: Model) {
  use _ <- effect.from()
  let none = fn() { Nil }
  let unsubscriber = option.unwrap(model.dom_click_unsubscriber, none)
  unsubscriber()
}

pub fn autocomplete_packages(model: Model, search: String) {
  case should_trigger_autocomplete_packages(model, search) {
    Error(_) -> Model(..model, autocomplete: None)
    Ok(search) -> {
      let autocomplete = autocomplete.init(model.packages, search)
      let autocomplete = #(Package, autocomplete)
      Model(..model, autocomplete: Some(autocomplete))
    }
  }
}

pub fn autocomplete_versions(model: Model, search: String) {
  case should_trigger_autocomplete_versions(model, search) {
    Error(_) -> #(model, effect.none())
    Ok(#(package, version)) -> {
      case dict.get(model.packages_versions, package) {
        Error(_) ->
          case list.contains(model.packages, package) {
            True -> #(model, effects.package_versions(package))
            False -> #(model, effect.none())
          }
        Ok(package) -> {
          let versions = list.map(package.releases, fn(r) { r.version })
          let autocomplete = autocomplete.init(versions, version)
          let autocomplete = #(Version, autocomplete)
          let model = Model(..model, autocomplete: Some(autocomplete))
          #(model, effect.none())
        }
      }
    }
  }
}

pub fn select_next_package(model: Model) -> Model {
  use autocomplete <- map_autocomplete(model)
  autocomplete.next(autocomplete)
}

pub fn select_previous_package(model: Model) -> Model {
  use autocomplete <- map_autocomplete(model)
  autocomplete.previous(autocomplete)
}

fn map_autocomplete(model: Model, mapper: fn(Autocomplete) -> Autocomplete) {
  case model.autocomplete {
    None -> model
    Some(#(type_, autocomplete)) -> {
      let autocomplete = mapper(autocomplete)
      let autocomplete = #(type_, autocomplete)
      let model = Model(..model, autocomplete: Some(autocomplete))
      update_displayed(model, autocomplete)
    }
  }
}

fn update_displayed(model: Model, autocomplete: #(Type, Autocomplete)) {
  let #(type_, autocomplete) = autocomplete
  case autocomplete.current(autocomplete), model.route, type_ {
    _, route.NotFound, _ -> model
    None, route.Home, _ ->
      Model(..model, home_input_displayed: model.home_input)
    None, route.Search(..), Package -> {
      Model(..model, search_packages_filter_input_displayed: {
        model.search_packages_filter_input
      })
    }
    None, route.Search(..), Version -> {
      Model(..model, search_packages_filter_version_input_displayed: {
        model.search_packages_filter_version_input
      })
    }
    Some(current), route.Home, _ -> {
      let home_input_displayed =
        replace_last_word(model.home_input_displayed, current, type_)
      Model(..model, home_input_displayed:)
    }
    Some(current), route.Search(..), Package -> {
      Model(..model, search_packages_filter_input_displayed: current)
    }
    Some(current), route.Search(..), Version -> {
      Model(..model, search_packages_filter_version_input_displayed: current)
    }
  }
}

/// When using the home search input, only the last word in the input should be
/// replaced when using the autocomplete. That helper helps by managing directly
/// the replacement.
fn replace_last_word(content: String, word: String, type_: Type) {
  case type_ {
    Package -> {
      let parts = string.split(content, on: " ")
      let length = list.length(parts)
      parts
      |> list.take(length - 1)
      |> list.append(["#" <> word])
      |> string.join(with: " ")
    }
    Version -> {
      let parts = string.split(content, on: " ")
      let length = list.length(parts)
      let start = list.take(parts, length - 1)
      case list.last(parts) {
        Error(_) -> string.join(parts, with: " ")
        Ok(last_word) -> {
          let segments = string.split(last_word, on: ":")
          let length = list.length(segments)
          list.take(segments, length - 1)
          |> list.append([word])
          |> string.join(with: ":")
          |> list.wrap
          |> list.append(start, _)
          |> string.join(with: " ")
        }
      }
    }
  }
}

/// Autocomplete is triggered on multiple cases:
/// - On home page (`model.route` is `route.Home`), when the user typed `#`,
///   the autocomplete will trigger.
/// - On search page (`model.route` is `route.Search(..)`), when the user
///   focuses the input, the autocomplete will instantly trigger.
/// `should_trigger_autocomplete_packages` returns the string to match on.
fn should_trigger_autocomplete_packages(model: Model, search: String) {
  let no_search = string.is_empty(search) || string.ends_with(search, " ")
  use <- bool.guard(when: no_search, return: Error(Nil))
  search
  |> string.split(on: " ")
  |> list.last
  |> result.try(fn(search) {
    let length = string.length(search)
    case
      string.starts_with(search, "#"),
      string.contains(search, ":"),
      model.route
    {
      _, True, _ -> Error(Nil)
      True, False, _ -> Ok(string.slice(from: search, at_index: 1, length:))
      False, _, route.Search(..) -> Ok(search)
      False, _, _ -> Error(Nil)
    }
  })
}

/// Autocomplete is triggered on multiple cases:
/// - On home page (`model.route` is `route.Home`), when the user typed `:`,
///   the autocomplete will trigger.
/// - On search page (`model.route` is `route.Search(..)`), when the user
///   focus the input, the autocomplete will instantly trigger
///   iif the package is correctly selected.
/// `should_trigger_autocomplete_packages` returns the string to match on.
fn should_trigger_autocomplete_versions(model: Model, search: String) {
  case model.route, search {
    route.NotFound, _ -> Error(Nil)
    route.Home, "" -> Error(Nil)
    route.Search(..), _ ->
      Ok(#(model.search_packages_filter_input_displayed, ""))
    route.Home, search -> {
      use <- bool.guard(when: string.ends_with(search, " "), return: Error(Nil))
      search
      |> string.split(on: " ")
      |> list.last
      |> result.try(fn(search) {
        let length = string.length(search)
        case string.starts_with(search, "#") {
          False -> Error(Nil)
          True ->
            case string.split(search, on: ":") {
              [word, version] ->
                Ok(#(string.slice(from: word, at_index: 1, length:), version))
              _ -> Error(Nil)
            }
        }
      })
    }
  }
}
