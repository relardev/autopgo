import Config

config :logger, :default_formatter, format: "$node | $level: $message $metadata\n"

config :autopgo, Autopgo.Scheduler,
  run_strategy: Quantum.RunStrategy.Local,
  overlap: false,
  jobs: [
    # Every minute
    autopgo: [
      schedule: "@hourly",
      task: &Autopgo.Task.go!/0
    ]
  ]

import_config "#{config_env()}.exs"
