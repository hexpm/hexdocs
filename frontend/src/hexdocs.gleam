import gleam/dict
import gleam/dynamic/decode
import gleam/function
import gleam/hexpm
import gleam/list
import gleam/option.{None, Some}
import gleam/pair
import gleam/result
import gleam/string
import grille_pain
import grille_pain/lustre/toast
import hexdocs/components/iframe
import hexdocs/data/model.{type Model, Model}
import hexdocs/data/model/autocomplete
import hexdocs/data/model/route
import hexdocs/data/msg.{type Msg}
import hexdocs/effects
import hexdocs/loss.{type Loss}
import hexdocs/services/hexdocs
import hexdocs/setup
import hexdocs/view/home
import hexdocs/view/search
import lustre
import lustre/effect.{type Effect}
import lustre/element/html
import modem

pub fn main() {
  let flags = Nil
  let assert Ok(_) = iframe.register()
  let assert Ok(_) = grille_pain.simple()
  lustre.application(setup.init, update, view)
  |> lustre.start("#app", flags)
}

pub fn view(model: Model) {
  case model.route {
    route.Home -> home.home(model)
    route.Search(..) -> search.search(model)
    route.NotFound -> html.div([], [])
  }
}

fn update(model: Model, msg: Msg) {
  case msg {
    msg.ApiReturnedPackageVersions(response) ->
      api_returned_package_versions(model, response)
    msg.ApiReturnedPackagesVersions(packages) ->
      api_returned_packages_versions(model, packages)
    msg.ApiReturnedPackages(response) -> api_returned_packages(model, response)
    msg.ApiReturnedTypesenseSearch(response) ->
      api_returned_typesense_search(model, response)

    msg.DocumentChangedLocation(location:) ->
      model.update_route(model, location)
    msg.DocumentRegisteredEventListener(unsubscriber:) ->
      document_registered_event_listener(model, unsubscriber)
    msg.DocumentRegisteredSidebarListener(unsubscriber:) ->
      document_registered_sidebar_listener(model, unsubscriber)
    msg.DocumentChangedTheme(theme) ->
      model.update_color_theme(model, theme)
      |> pair.new(effect.none())

    msg.UserToggledDarkMode -> user_toggled_dark_mode(model)
    msg.UserToggledSidebar -> model.toggle_sidebar(model)
    msg.UserClosedSidebar -> model.close_sidebar(model)
    msg.UserClickedGoBack -> user_clicked_go_back(model)

    msg.UserFocusedSearch -> user_focused_search(model)
    msg.UserBlurredSearch -> model.blur_search(model)

    msg.UserEditedSearch(search:) -> model.update_home_search(model, search)
    msg.UserClickedAutocompletePackage(package:) ->
      user_clicked_autocomplete_package(model, package)
    msg.UserSelectedNextAutocompletePackage ->
      user_selected_next_autocomplete_package(model)
    msg.UserSelectedPreviousAutocompletePackage ->
      user_selected_previous_autocomplete_package(model)
    msg.UserSubmittedSearch -> user_submitted_search(model)
    msg.UserSubmittedAutocomplete -> user_submitted_autocomplete(model)

    msg.UserDeletedPackagesFilter(filter) ->
      user_deleted_packages_filter(model, filter)
    msg.UserEditedSearchInput(search_input:) ->
      user_edited_search_input(model, search_input)
    msg.UserSubmittedPackagesFilter -> user_submitted_packages_filter(model)
    msg.UserSubmittedSearchInput -> user_submitted_search_input(model)
    msg.UserEditedPackagesFilterInput(content) ->
      user_edited_packages_filter_input(model, content)
    msg.UserEditedPackagesFilterVersion(content) ->
      user_edited_packages_filter_version(model, content)
    msg.UserFocusedPackagesFilterInput ->
      user_focused_packages_filter_input(model)
    msg.UserFocusedPackagesFilterVersion ->
      user_focused_packages_filter_version_input(model)
    msg.UserToggledPreview(id) -> user_toggled_preview(model, id)
    msg.UserSelectedPackageFilter -> user_selected_package_filter(model)
    msg.UserSelectedPackageFilterVersion ->
      user_selected_package_filter_version(model)
    msg.UserClickedShare -> #(model, {
      effect.batch([
        effect.from(fn(_) { copy_url() }),
        toast.info("The current URL has been copied in your clipboard."),
      ])
    })

    msg.None -> #(model, effect.none())
  }
}

fn api_returned_package_versions(
  model: Model,
  response: Loss(hexpm.Package),
) -> #(Model, Effect(Msg)) {
  case response {
    Error(_) -> #(model, toast.error("Server error. Retry later."))
    Ok(package) -> {
      model
      |> model.add_packages_versions([package])
      |> model.focus_home_search
    }
  }
}

fn api_returned_packages_versions(
  model: Model,
  packages: Loss(List(hexpm.Package)),
) -> #(Model, Effect(Msg)) {
  case packages {
    Error(_) -> #(model, toast.error("Server error. Retry later."))
    Ok(packages) -> {
      model
      |> model.add_packages_versions(packages)
      |> model.compute_filters_input
    }
  }
}

fn api_returned_packages(
  model: Model,
  response: Loss(String),
) -> #(Model, Effect(msg)) {
  case response {
    Error(_) -> #(model, toast.error("Server error. Retry later."))
    Ok(packages) ->
      packages
      |> string.split(on: "\n")
      |> model.add_packages(model, _)
      |> pair.new(effect.none())
  }
}

fn api_returned_typesense_search(model: Model, response: Loss(decode.Dynamic)) {
  response
  |> result.try(fn(search_result) {
    search_result
    |> decode.run(hexdocs.typesense_decoder())
    |> result.map_error(loss.DecodeError)
  })
  |> result.map(model.set_search_results(model, _))
  |> result.map(pair.new(_, effect.none()))
  |> result.unwrap(#(model, effect.none()))
}

fn document_registered_event_listener(model: Model, unsubscriber: fn() -> Nil) {
  let dom_click_unsubscriber = Some(unsubscriber)
  Model(..model, dom_click_unsubscriber:)
  |> pair.new(effect.none())
}

fn document_registered_sidebar_listener(model: Model, unsubscriber: fn() -> Nil) {
  let dom_click_sidebar_unsubscriber = Some(unsubscriber)
  Model(..model, dom_click_sidebar_unsubscriber:)
  |> pair.new(effect.none())
}

fn user_toggled_dark_mode(model: Model) {
  let model = model.toggle_dark_theme(model)
  #(model, {
    use _ <- effect.from()
    update_color_theme(case model.dark_mode.mode {
      msg.Dark -> "dark"
      msg.Light -> "light"
    })
  })
}

fn user_submitted_search(model: Model) {
  case model.autocomplete {
    None -> model.compute_filters_input(model)
    Some(#(_, autocomplete)) -> {
      case autocomplete.current(autocomplete) {
        None -> model.compute_filters_input(model)
        Some(_) ->
          model.update_home_search(model, model.home_input_displayed <> " ")
      }
    }
  }
}

fn user_submitted_autocomplete(model: Model) {
  case model.autocomplete {
    None -> #(model, effect.none())
    Some(#(model.Version, autocomplete)) -> {
      case autocomplete.current(autocomplete) {
        None -> #(model, effect.none())
        Some(_) ->
          model.update_home_search(model, model.home_input_displayed <> " ")
      }
    }
    Some(#(model.Package, autocomplete)) -> {
      case autocomplete.current(autocomplete) {
        None -> #(model, effect.none())
        Some(_) ->
          model.update_home_search(model, model.home_input_displayed <> ":")
      }
    }
  }
}

fn user_edited_search_input(model: Model, search_input: String) {
  Model(..model, search_input:)
  |> pair.new(effect.none())
}

fn user_edited_packages_filter_input(model: Model, content: String) {
  Model(
    ..model,
    search_packages_filter_input: content,
    search_packages_filter_input_displayed: content,
  )
  |> model.autocomplete_packages(content)
  |> function.tap(fn(m) { m.autocomplete })
  |> pair.new(effect.none())
}

fn user_edited_packages_filter_version(model: Model, content: String) {
  Model(
    ..model,
    search_packages_filter_version_input: content,
    search_packages_filter_version_input_displayed: content,
  )
  |> pair.new(effect.none())
}

fn user_submitted_search_input(model: Model) {
  #(model, {
    route.push({
      route.Search(
        q: model.search_input,
        packages: model.search_packages_filters,
      )
    })
  })
}

fn user_focused_search(model: Model) {
  let #(model, effect) = model.focus_home_search(model)
  let effects = effect.batch([effect, effects.subscribe_blurred_search()])
  #(model, effects)
}

fn user_selected_next_autocomplete_package(model: Model) {
  model
  |> model.select_next_package
  |> pair.new(effect.none())
}

fn user_selected_previous_autocomplete_package(model: Model) {
  model
  |> model.select_previous_package
  |> pair.new(effect.none())
}

fn user_clicked_autocomplete_package(model: Model, package: String) {
  model
  |> model.select_autocomplete_option(package)
  |> model.blur_search
  |> pair.map_second(fn(effects) {
    let versions = case model.autocomplete {
      None -> effect.none()
      Some(#(model.Version, _)) -> effect.none()
      Some(#(model.Package, _)) -> effects.package_versions(package)
    }
    effect.batch([versions, effects])
  })
}

fn user_deleted_packages_filter(
  model: Model,
  filter: #(String, String),
) -> #(Model, Effect(msg)) {
  let search_packages_filters =
    list.filter(model.search_packages_filters, fn(f) { f != filter })
  let model = Model(..model, search_packages_filters:)
  #(model, {
    route.push(route.Search(
      q: model.search_input,
      packages: model.search_packages_filters,
    ))
  })
}

fn user_clicked_go_back(model: Model) -> #(Model, Effect(msg)) {
  #(model, modem.back(1))
}

fn user_submitted_packages_filter(model: Model) {
  let package = model.search_packages_filter_input
  let version = model.search_packages_filter_version_input
  model.packages_versions
  |> dict.get(package)
  |> result.map(fn(package) { package.releases })
  |> result.try(list.find(_, fn(r) { r.version == version }))
  |> result.map(fn(_) {
    let search_packages_filters =
      [#(package, version)]
      |> list.append(model.search_packages_filters, _)
      |> list.unique
    let model =
      Model(
        ..model,
        search_packages_filters:,
        search_packages_filter_input: "",
        search_packages_filter_input_displayed: "",
        search_packages_filter_version_input: "",
        search_packages_filter_version_input_displayed: "",
      )
    route.Search(q: model.search_input, packages: model.search_packages_filters)
    |> route.push
    |> pair.new(model, _)
  })
  |> result.lazy_unwrap(fn() { #(model, effect.none()) })
}

fn user_focused_packages_filter_input(model: Model) {
  let model = model.focus_packages_filter_search(model)
  let effect = effects.subscribe_blurred_search()
  #(model, effect)
}

fn user_focused_packages_filter_version_input(
  model: Model,
) -> #(Model, Effect(Msg)) {
  let #(model, effect) = model.focus_packages_filter_version_search(model)
  let effects = effect.batch([effects.subscribe_blurred_search(), effect])
  #(model, effects)
}

fn user_toggled_preview(model: Model, id: String) {
  Model(..model, search_opened_previews: {
    use opened <- dict.upsert(model.search_opened_previews, id)
    let opened = option.unwrap(opened, False)
    !opened
  })
  |> pair.new(effect.none())
}

fn user_selected_package_filter(model: Model) {
  case model.get_selected_package_filter_name(model) {
    Error(_) -> #(model, effect.none())
    Ok(package) -> {
      Model(
        ..model,
        search_packages_filter_input_displayed: package,
        search_packages_filter_input: package,
      )
      |> model.blur_search
      |> pair.map_second(fn(blur_effect) {
        let submit_package_input = effect.from(fn(_) { submit_package_input() })
        effect.batch([blur_effect, submit_package_input])
      })
    }
  }
}

fn user_selected_package_filter_version(model: Model) {
  let package = model.search_packages_filter_input_displayed
  let version = model.search_packages_filter_version_input_displayed
  let releases =
    model.packages_versions
    |> dict.get(package)
    |> result.map(fn(p) { p.releases })
    |> result.unwrap([])
  let release =
    releases
    |> list.find(fn(r) { r.version == version })
    |> result.try_recover(fn(_) { list.first(releases) })
  case release {
    Error(_) -> #(model, effect.none())
    Ok(release) -> {
      let model =
        Model(
          ..model,
          search_packages_filter_version_input: release.version,
          search_packages_filter_version_input_displayed: release.version,
        )
      let #(model, effect1) = model.blur_search(model)
      let #(model, effect2) = user_submitted_packages_filter(model)
      #(model, effect.batch([effect1, effect2]))
    }
  }
}

@external(javascript, "./hexdocs.ffi.mjs", "submitPackageInput")
fn submit_package_input() -> Nil

@external(javascript, "./hexdocs.ffi.mjs", "updateColorTheme")
fn update_color_theme(color_mode: String) -> Nil

@external(javascript, "./hexdocs.ffi.mjs", "copyUrl")
fn copy_url() -> Nil
