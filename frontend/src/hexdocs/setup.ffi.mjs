export function readDarkMode() {
  const [custom, theme] = doReadDarkMode()
  if (theme === "dark") document.documentElement.classList.add("dark")
  if (theme === "light") document.documentElement.classList.add("light")
  return [custom, theme]
}

function doReadDarkMode() {
  const theme = window.localStorage.getItem("theme")
  if (theme === null) return readSystemMode()
  if (!["light", "dark"].includes(theme)) return readSystemMode()
  return ["user", theme]
}

function readSystemMode() {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  if (isDark) return ["system", "dark"]
  return ["system", "light"]
}

export function watchIsDark(callback) {
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", (event) => {
      if (event.matches) return callback("dark")
      if (!event.matches) return callback("light")
    })
}
