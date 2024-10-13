import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo/test/nodes/3",
  profile_dir: "/home/user/workspace/autopgo/test/nodes/3/pprof",
  default_pprof_path: "/home/user/workspace/autopgo/test/nodes/3/default.pprof",
  run_dir: "/home/user/workspace/autopgo/test/nodes/3/",
  run_command: "app --port=:8083",
  recompile_command: "go build -pgo={{profile}} -o test/nodes/3/app app/main.go",
  profile_url: "http://localhost:8083/debug/pprof/profile?seconds=14",
  liveness_url: "http://localhost:8083/check",
  readiness_url: "http://localhost:8083/check",
  memory_monitor: "fake",
  port: 4003,
  first_profile_in_seconds: 3,
  clustering: :local
