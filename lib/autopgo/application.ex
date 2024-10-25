defmodule Autopgo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    dbg(Application.get_all_env(:autopgo))
    run_command = Application.get_env(:autopgo, :run_command)

    {available_memory_files, used_memory_files} =
      case Application.get_env(:autopgo, :memory_monitor, "file") do
        "fake" ->
          {nil, nil}

        "cgroups" ->
          {
            [
              "/sys/fs/cgroup/memory/memory.limit_in_bytes",
              "/sys/fs/cgroup/memory.max"
            ],
            [
              "/sys/fs/cgroup/memory/memory.usage_in_bytes",
              "/sys/fs/cgroup/memory.current"
            ]
          }

        _ ->
          {
            [Application.get_env(:autopgo, :available_memory_file)],
            [Application.get_env(:autopgo, :used_memory_file)]
          }
      end

    children =
      cluster(Application.get_env(:autopgo, :clustering, :dns)) ++
        [
          {Autopgo.BinaryStore,
           %{
             run_dir: Application.get_env(:autopgo, :run_dir),
             run_command: run_command
           }},
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
             available_memory_files: available_memory_files,
             used_memory_files: used_memory_files,
             fake: Application.get_env(:autopgo, :memory_monitor) == "fake"
           }},
          {Healthchecks,
           %{
             liveness_url: Application.get_env(:autopgo, :liveness_url),
             readiness_url: Application.get_env(:autopgo, :readiness_url)
           }},
          {Autopgo.AppSupervisor,
           %{
             run_dir: Application.get_env(:autopgo, :run_dir),
             run_command: run_command,
             autopgo_dir: Application.get_env(:autopgo, :autopgo_dir)
           }},
          {Autopgo.Worker, %{}},
          {Task.Supervisor, name: Autopgo.Compilation.TaskSupervisor},
          {Autopgo.WebController, %{}},
          {Highlander, Autopgo.LoopingController},
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
    query = Application.get_env(:autopgo, :dns_query)
    Logger.info("Starting cluster with DNS poll, query: #{query}")

    topologies = [
      dns_poll: [
        strategy: Elixir.Cluster.Strategy.DNSPoll,
        config: [
          query: query,
          node_basename: "autopgo",
          resolver: fn query ->
            query
            |> String.to_charlist()
            |> :inet.gethostbyname()
            |> case do
              {:ok, {:hostent, _name, _aliases, _addr_type, _length, ip_list}} -> ip_list
              {:error, _} -> []
            end
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
