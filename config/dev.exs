import Config

config :autopgo,
    run_command: "app/app",
    recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
    profile_url: "http://localhost:8080/debug/pprof/profile?seconds=5",
    liveness_url: "http://localhost:8080/check",
    readiness_url: "http://localhost:8080/check"
