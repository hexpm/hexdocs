import browser/window/location

@external(javascript, "./window/location.ffi.mjs", "location")
pub fn location() -> Result(location.Location, Nil)
