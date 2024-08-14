import Config

config :autopgo,
    autopgo_dir: "/home/user/workspace/autopgo",
    run_dir: "/home/user/workspace/autopgo/app/",
    run_command: "app",
    recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
    profile_url: "http://localhost:8080/debug/pprof/profile?seconds=5",
    liveness_url: "http://localhost:8080/check",
    readiness_url: "http://localhost:8080/check"
