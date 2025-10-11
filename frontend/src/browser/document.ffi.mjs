export function addDocumentListener(callback) {
  document.addEventListener("click", callback, { once: true })
  return () => document.removeEventListener("click", callback)
}
