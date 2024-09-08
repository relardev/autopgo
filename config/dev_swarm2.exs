import Config

config :autopgo,
  autopgo_dir: "/home/user/workspace/autopgo/test/nodes/2",
  profile_dir: "/home/user/workspace/autopgo/test/nodes/2/pprof",
  run_dir: "/home/user/workspace/autopgo/test/nodes/2/",
  run_command: "app --port=:8082",
  recompile_command: "go build -pgo=default.pprof -o test/nodes/2/app app/main.go",
  profile_url: "http://localhost:8082/debug/pprof/profile?seconds=14",
  liveness_url: "http://localhost:8082/check",
  readiness_url: "http://localhost:8082/check",
  fake_memory_monitor: true,
  port: 4002,
  clustering: :local
