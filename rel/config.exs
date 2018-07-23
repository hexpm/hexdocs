use Mix.Releases.Config,
    default_release: :default,
    default_environment: :prod

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(post_configure_hook: "rel/hooks/typonf.sh")
end

release :hexdocs do
  set(version: current_version(:hexdocs))
end
