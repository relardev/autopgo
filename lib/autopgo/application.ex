defmodule Autopgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    File.rm_rf!("pprof")
    File.rm_rf!("default.pprof")
    File.mkdir_p!("pprof")

    dbg(Application.get_all_env(:autopgo))

    dns = Application.get_env(:autopgo, :dns, "")

    children = cluster(dns) ++ [
      {Autopgo.MemoryMonitor, %{
        available_memory_file: Application.get_env(:autopgo, :available_memory_file),
        used_memory_file: Application.get_env(:autopgo, :used_memory_file),
      }},
      {Autopgo.Worker, %{
        run_dir: Application.get_env(:autopgo, :run_dir),
        run_command: Application.get_env(:autopgo, :run_command),
        recompile_command: Application.get_env(:autopgo, :recompile_command),
        profile_url: Application.get_env(:autopgo, :profile_url),
        autopgo_dir: Application.get_env(:autopgo, :autopgo_dir),
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
      {Autopgo.LoopingController, %{
        initial_profile_delay: 5*60*1000,
        recompile_interval: 10*60*1000,
        retry_interval: 1000,
      }},
      {Bandit, plug: ServerPlug},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Autopgo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cluster(""), do: []
  defp cluster(dns) do
    topologies = [
      dns: [
        strategy: Elixir.Cluster.Strategy.DNSPoll,
        config: [
          polling_interval: 5_000,
          query: dns,
          node_basename: "autopgo",
        ]
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Autopgo.ClusterSupervisor]]},
    ]
  end
end
