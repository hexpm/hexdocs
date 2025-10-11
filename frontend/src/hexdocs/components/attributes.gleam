import gleam/int
import lustre/component

pub fn string(name: String, msg: fn(String) -> msg) -> component.Option(msg) {
  use content <- component.on_attribute_change(name)
  Ok(msg(content))
}

pub fn int(name: String, msg: fn(Int) -> a) -> component.Option(a) {
  use content <- component.on_attribute_change(name)
  case int.parse(content) {
    Ok(content) -> Ok(msg(content))
    Error(_) -> Error(Nil)
  }
}
