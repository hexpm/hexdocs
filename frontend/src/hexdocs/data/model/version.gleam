import gleam/option.{type Option, None, Some}
import gleam/regexp

const version_regexp = "^#([a-zA-Z_0-9]+)(:(([0-9]+|\\.){1,5}))?"

pub fn match_package(word: String) -> Result(#(String, Option(String)), Nil) {
  let regexp = version_search()
  case regexp.scan(regexp, word) {
    [regexp.Match(content: _, submatches:)] -> {
      case submatches {
        [Some(package), _, Some(version), ..] -> Ok(#(package, Some(version)))
        [Some(package)] -> Ok(#(package, None))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn to_string(package: #(String, String)) {
  let #(package, version) = package
  let package = "#" <> package
  package <> ":" <> version
}

fn version_search() {
  let options = regexp.Options(case_insensitive: False, multi_line: False)
  let assert Ok(regexp) = regexp.compile(version_regexp, with: options)
  regexp
}
