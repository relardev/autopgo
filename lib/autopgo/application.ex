defmodule Autopgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # File.rm_rf!("pprof")
    # File.rm_rf!("default.pprof")
    # File.mkdir_p!("pprof")

    dbg(Application.get_all_env(:autopgo))

    children =
      cluster(Application.get_env(:autopgo, :clustering, :dns)) ++
        [
          {Autopgo.BinaryStore, %{}},
          {Autopgo.GoCompiler, %{}},
          {Autopgo.ProfileManager,
           %{
             url: Application.get_env(:autopgo, :profile_url),
             profile_dir: Application.get_env(:autopgo, :profile_dir, "pprof"),
             default_pprof_path:
               Application.get_env(:autopgo, :default_pprof_path, "default.pprof")
           }},
          {Autopgo.MemoryMonitor,
           %{
             available_memory_file: Application.get_env(:autopgo, :available_memory_file),
             used_memory_file: Application.get_env(:autopgo, :used_memory_file),
             fake: Application.get_env(:autopgo, :fake_memory_monitor, false)
           }},
          {Healthchecks,
           %{
             liveness_url: Application.get_env(:autopgo, :liveness_url),
             readiness_url: Application.get_env(:autopgo, :readiness_url)
           }},
          {Autopgo.Worker,
           %{
             run_dir: Application.get_env(:autopgo, :run_dir),
             run_command: Application.get_env(:autopgo, :run_command),
             autopgo_dir: Application.get_env(:autopgo, :autopgo_dir)
           }},
          {Task.Supervisor, name: Autopgo.Compilation.TaskSupervisor},
          {Autopgo.WebController, %{}},
          {Watchdog, processes: [Autopgo.LoopingController]},
          {Bandit, plug: ServerPlug, port: Application.get_env(:autopgo, :port, 4000)}
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Autopgo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cluster(:no_cluster), do: []

  defp cluster(:local) do
    Logger.info("Starting cluster with local epmd")

    topologies = [
      local_epmd_example: [
        strategy: Elixir.Cluster.Strategy.LocalEpmd
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Autopgo.ClusterSupervisor]]}
    ]
  end

  defp cluster(:dns) do
    Logger.info("Starting cluster with DNS poll")

    topologies = [
      dns_poll: [
        strategy: Elixir.Cluster.Strategy.DNSPoll,
        config: [
          query: "kafkalogger",
          node_basename: "autopgo",
          resolver: fn query ->
            {:ok, {:hostent, _name, _aliases, _addr_type, _length, ip_list}} =
              query
              |> String.to_charlist()
              |> :inet.gethostbyname()

            ip_list
          end
        ]
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Autopgo.ClusterSupervisor]]}
    ]
  end

  defp cluster(:kubernetes) do
    selector = Application.get_env(:autopgo, :kubernetes_selector, "")
    Logger.info("Starting cluster with kubernetes_selector: #{selector}")

    topologies = [
      erlang_nodes_in_k8s: [
        strategy: Elixir.Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_node_basename: "autopgo",
          kubernetes_ip_lookup_mode: :pods,
          kubernetes_selector: selector,
          kubernetes_namespace: "default",
          polling_interval: 5_000
        ]
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Autopgo.ClusterSupervisor]]}
    ]
  end
end
