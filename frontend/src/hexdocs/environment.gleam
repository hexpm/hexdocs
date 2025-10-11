import browser/window
import browser/window/location
import gleam/result

pub type Environment {
  Development
  Staging
  Production
}

/// Read `GLEAM_ENV` environment variable to detect the global environment.
/// `GLEAM_ENV` should be `"production"`, `"staging"` or `"development"`. In case
/// `GLEAM_ENV` is missing, it fallback automatically on `Production` to avoid
/// potential leaking of critical data.
pub fn read() {
  let location = window.location()
  let hostname = result.map(location, location.hostname)
  case hostname {
    Ok("localhost") | Ok("127.0.0.1") -> Development
    Ok("staging" <> _) -> Staging
    _ -> Production
  }
}
