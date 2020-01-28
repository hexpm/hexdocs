import Config

config :rollbax, enabled: false

config :logger, :console, format: "[$level] $metadata$message\n"

import_config "#{Mix.env()}.exs"
