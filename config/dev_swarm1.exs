import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo/test/nodes/1",
  profile_dir: "/home/user/workspace/autopgo/test/nodes/1/pprof",
  default_pprof_path: "/home/user/workspace/autopgo/test/nodes/1/default.pprof",
  run_dir: "/home/user/workspace/autopgo/test/nodes/1/",
  run_command: "app --port=:8081",
  recompile_command: "go build -pgo={{profile}} -o test/nodes/1/app app/main.go",
  profile_url: "http://localhost:8081/debug/pprof/profile?seconds=14",
  liveness_url: "http://localhost:8081/check",
  readiness_url: "http://localhost:8081/check",
  memory_monitor: "fake",
  port: 4001,
  first_profile_in_seconds: 3,
  clustering: :local
