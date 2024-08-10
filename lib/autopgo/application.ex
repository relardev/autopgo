defmodule Autopgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    File.rm_rf!("pprof")
    File.rm_rf!("default.pprof")
    File.mkdir_p!("pprof")


    dbg(Application.get_all_env(:autopgo))

    children = [
      {Autopgo.Worker, %{
        binary_path: Application.get_env(:autopgo, :binary_path),
        recompile_command: Application.get_env(:autopgo, :recompile_command),
        profile_url: Application.get_env(:autopgo, :profile_url),
      }},
      {Healthchecks, %{
        liveness_url: Application.get_env(:autopgo, :liveness_url),
        readiness_url: Application.get_env(:autopgo, :readiness_url),
      }},
      {Autopgo.WebController, %{}},
      # {Autopgo.LoopingController, %{
      #   initial_profile_delay: 1000,
      #   recompile_interval: 1000,
      #   retry_interval: 1000,
      # }},
      # {Autopgo.LoopingController, %{
      #   initial_profile_delay: 15*60*1000,
      #   recompile_interval: 60*60*1000,
      #   retry_interval: 1000,
      # }},
      {Bandit, plug: ServerPlug},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Autopgo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
