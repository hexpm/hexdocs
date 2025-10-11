import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Zipper, providing a visualisation of an element of an autocompleted list.
/// Current value can be obtained using `current`, while the entire list can be
/// obtained through `all` for display purposes.
pub opaque type Autocomplete {
  Autocomplete(
    all: List(String),
    previous: List(String),
    current: Option(String),
    next: List(String),
  )
}

/// Initialise the current autocomplete, with no current selected element.
pub fn init(options: List(String), search: String) -> Autocomplete {
  let options = keep_first_ten_options(options, search)
  Autocomplete(all: options, previous: [], current: None, next: options)
}

pub fn all(autocomplete: Autocomplete) -> List(String) {
  autocomplete.all
}

pub fn current(autocomplete: Autocomplete) -> Option(String) {
  autocomplete.current
}

pub fn is_selected(autocomplete: Autocomplete, element: String) -> Bool {
  autocomplete.current == Some(element)
}

/// Select the next element. If there's no next element, nothing happens.
pub fn next(autocomplete: Autocomplete) -> Autocomplete {
  case autocomplete {
    Autocomplete(next: [], ..) -> autocomplete
    Autocomplete(next: [fst, ..next], current: None, ..) ->
      Autocomplete(..autocomplete, current: Some(fst), next:)
    Autocomplete(next: [fst, ..next], current: Some(c), ..) -> {
      let previous = [c, ..autocomplete.previous]
      let current = Some(fst)
      Autocomplete(..autocomplete, previous:, current:, next:)
    }
  }
}

/// Select the previous element. If there's no previous element, current element
/// is deselected. If there's no previous element & no current element, nothing
/// happens.
pub fn previous(autocomplete: Autocomplete) -> Autocomplete {
  case autocomplete {
    Autocomplete(previous: [], current: None, ..) -> autocomplete
    Autocomplete(previous: [], current: Some(c), next:, ..) ->
      Autocomplete(..autocomplete, next: [c, ..next], current: None)
    Autocomplete(previous: [fst, ..previous], current: Some(c), next:, ..) -> {
      let current = Some(fst)
      Autocomplete(..autocomplete, previous:, current:, next: [c, ..next])
    }
    _ -> panic as "previous cannot be filled if current is None"
  }
}

fn keep_first_ten_options(options: List(String), search: String) {
  options
  |> list.filter(string.starts_with(_, search))
  |> list.take(10)
}
