import Config

config :autopgo,
    autopgo_dir: "/home/user/workspace/autopgo/test/nodes/2",
    run_dir: "/home/user/workspace/autopgo/app/",
    run_command: "app --port=:8082",
    recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
    profile_url: "http://localhost:8082/debug/pprof/profile?seconds=5",
    liveness_url: "http://localhost:8082/check",
    readiness_url: "http://localhost:8082/check",
    fake_memory_monitor: true,
    port: 4002
