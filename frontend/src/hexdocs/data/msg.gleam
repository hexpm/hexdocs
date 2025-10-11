import gleam/dynamic.{type Dynamic}
import gleam/hexpm
import gleam/uri
import hexdocs/loss.{type Loss}

pub type Msg {
  // API messages.
  ApiReturnedPackageVersions(response: Loss(hexpm.Package))
  ApiReturnedPackages(Loss(String))
  ApiReturnedTypesenseSearch(Loss(Dynamic))
  ApiReturnedPackagesVersions(packages: Loss(List(hexpm.Package)))

  // Application messages.
  DocumentChangedLocation(location: uri.Uri)
  DocumentRegisteredEventListener(unsubscriber: fn() -> Nil)
  DocumentRegisteredSidebarListener(unsubscriber: fn() -> Nil)
  DocumentChangedTheme(color_theme: ColorMode)
  UserClickedGoBack
  UserToggledDarkMode
  UserToggledSidebar
  UserClosedSidebar

  // Home page messages.
  UserBlurredSearch
  UserClickedAutocompletePackage(package: String)
  UserEditedSearch(search: String)
  UserFocusedSearch
  UserSelectedNextAutocompletePackage
  UserSelectedPreviousAutocompletePackage
  UserSubmittedSearch
  UserSubmittedAutocomplete

  // Search page messages.
  UserDeletedPackagesFilter(#(String, String))
  UserEditedPackagesFilterInput(String)
  UserEditedPackagesFilterVersion(String)
  UserEditedSearchInput(search_input: String)
  UserFocusedPackagesFilterInput
  UserFocusedPackagesFilterVersion
  UserSelectedPackageFilter
  UserSelectedPackageFilterVersion
  UserSubmittedPackagesFilter
  UserSubmittedSearchInput
  UserToggledPreview(id: String)
  UserClickedShare

  // Neutral element, because we need to call `stop_propagation` conditionnally.
  None
}

pub type ColorSetting {
  User(mode: ColorMode)
  System(mode: ColorMode)
}

pub type ColorMode {
  Light
  Dark
}
