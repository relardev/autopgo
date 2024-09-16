import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo",
  run_dir: "/home/user/workspace/autopgo/app/",
  run_command: "app",
  recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
  profile_url: "http://localhost:8080/debug/pprof/profile?seconds=5",
  liveness_url: "http://localhost:8080/check",
  readiness_url: "http://localhost:8080/check",
  available_memory_file: "./available_memory",
  used_memory_file: "./used_memory",
  swarm_controller: false,
  clustering: :no_cluster,
  tick_ms: 1000,
  recomplie_interval_seconds: 60,
  first_profile_in_seconds: 3
