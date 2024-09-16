import Config

config :logger, :default_formatter, format: "$node | $level: $message $metadata\n"

import_config "#{config_env()}.exs"
