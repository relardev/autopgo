import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo/test/nodes/2",
  profile_dir: "/home/user/workspace/autopgo/test/nodes/2/pprof",
  default_pprof_path: "/home/user/workspace/autopgo/test/nodes/2/default.pprof",
  run_dir: "/home/user/workspace/autopgo/test/nodes/2/",
  run_command: "app --port=:8082",
  recompile_command: "go build -pgo={{profile}} -o test/nodes/2/app app/main.go",
  profile_url: "http://localhost:8082/debug/pprof/profile?seconds=14",
  liveness_url: "http://localhost:8082/check",
  readiness_url: "http://localhost:8082/check",
  memory_monitor: "fake",
  port: 4002,
  first_profile_in_seconds: 3,
  clustering: :local
