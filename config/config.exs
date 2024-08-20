import Config

config :logger, :default_formatter,
  format: "[Autopgo]: |$level| $message $metadata\n"

import_config "#{config_env()}.exs"
