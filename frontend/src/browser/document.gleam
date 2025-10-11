/// Subscribes to a click on the DOM, and returns an unsubscriber.
@external(javascript, "./document.ffi.mjs", "addDocumentListener")
pub fn add_listener(callback: fn() -> Nil) -> fn() -> Nil
