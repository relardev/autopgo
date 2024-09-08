import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo/test/nodes/3",
  profile_dir: "/home/user/workspace/autopgo/test/nodes/3/pprof",
  run_dir: "/home/user/workspace/autopgo/test/nodes/3/",
  run_command: "app --port=:8083",
  recompile_command: "go build -pgo=default.pprof -o test/nodes/3/app app/main.go",
  profile_url: "http://localhost:8083/debug/pprof/profile?seconds=14",
  liveness_url: "http://localhost:8083/check",
  readiness_url: "http://localhost:8083/check",
  fake_memory_monitor: true,
  port: 4003,
  clustering: :local
