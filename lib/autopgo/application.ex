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

    kubernetes_selector = Application.get_env(:autopgo, :kubernetes_selector, "")

    children = cluster(kubernetes_selector) ++ [
      {Autopgo.MemoryMonitor, %{
        available_memory_file: Application.get_env(:autopgo, :available_memory_file),
        used_memory_file: Application.get_env(:autopgo, :used_memory_file),
        fake: Application.get_env(:autopgo, :fake_memory_monitor, false),
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
      # {Bandit, plug: ServerPlug, port: Application.get_env(:autopgo, :port, 4000)},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Autopgo.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

     :ok = case Swarm.register_name(:looping_controller, Autopgo.LoopingController, :start_link, [%{
      initial_profile_delay: 5 * 60 * 1000,
      recompile_interval: 10 * 60 * 1000,
      retry_interval: 1000
    }]) do
      {:ok, _pid} ->
        Logger.info("Looping controller started on node #{Node.self()}")
        :ok

      {:error, {:already_registered, _pid}} ->
        Logger.info("Looping controller already started, skipping on node #{Node.self()}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
    {:ok, pid}
  end

  defp cluster(""), do: []
  defp cluster(kubernetes_selector) do
    Logger.info("Starting cluster with kubernetes_selector: #{kubernetes_selector}")
    topologies = [
      erlang_nodes_in_k8s: [
        strategy: Elixir.Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_node_basename: "autopgo",
          kubernetes_ip_lookup_mode: :pods,
          kubernetes_selector: kubernetes_selector,
          kubernetes_namespace: "default",
          polling_interval: 10_000
        ]
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Autopgo.ClusterSupervisor]]},
    ]
  end
end
