import * as gleam from "../../gleam.mjs"

export function location() {
  if (typeof window === "undefined") return new gleam.Error()
  return new gleam.Ok(window.location)
}

export const hash = (location) => location.hash
export const host = (location) => location.host
export const hostname = (location) => location.hostname
export const href = (location) => location.href
export const origin = (location) => location.origin
export const pathname = (location) => location.pathname
export const port = (location) => location.port
export const protocol = (location) => location.protocol
export const search = (location) => location.search
