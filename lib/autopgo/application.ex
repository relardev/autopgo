defmodule Autopgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Autopgo.Worker, %{
        binary_path: "app/app", 
        recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
        profile_url: "http://localhost:8080/debug/pprof/profile\?seconds\=5",
      }},
      {Bandit, plug: ServerPlug},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Autopgo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
