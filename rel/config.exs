use Mix.Releases.Config,
    default_release: :default,
    default_environment: :prod

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(pre_configure_hooks: "rel/hooks/pre_configure")
end

release :hexdocs do
  set(version: current_version(:hexdocs))
  set(cookie: "")
  set(vm_args: "rel/vm.args")
end
