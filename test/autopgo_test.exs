# defmodule AutopgoTest do
#   use ExUnit.Case
#   doctest Autopgo
#
#   test "greets the world" do
#     assert :world == :world
#   end
# end

defmodule AutopgoClusterTest do
  # Use the module
  use ExUnit.ClusteredCase

  @opts [
    cluster_size: 2,
    boot_timeout: 10_000,
    capture_log: true,
    nodes: [
      [
        name: :"ex_unit_clustered_node_1@127.0.0.1",
        config: [
          autopgo: [
            autopgo_dir: "/home/user/workspace/autopgo/test/nodes/1",
            run_dir: "/home/user/workspace/autopgo/app/",
            run_command: "app --port=:8081",
            recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
            profile_url: "http://localhost:8081/debug/pprof/profile?seconds=5",
            liveness_url: "http://localhost:8081/check",
            readiness_url: "http://localhost:8081/check",
            memory_monitor: "fake",
            port: 4001
          ]
        ]
      ],
      [
        name: :"ex_unit_clustered_node_2@127.0.0.1",
        config: [
          autopgo: [
            autopgo_dir: "/home/user/workspace/autopgo/test/nodes/2",
            run_dir: "/home/user/workspace/autopgo/app/",
            run_command: "app --port=:8082",
            recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
            profile_url: "http://localhost:8082/debug/pprof/profile?seconds=5",
            liveness_url: "http://localhost:8082/check",
            readiness_url: "http://localhost:8082/check",
            memory_monitor: "fake",
            port: 4002
          ]
        ]
      ],
      [
        name: :"ex_unit_clustered_node_3@127.0.0.1",
        config: [
          autopgo: [
            autopgo_dir: "/home/user/workspace/autopgo/test/nodes/3",
            run_dir: "/home/user/workspace/autopgo/app/",
            run_command: "app --port=:8083",
            recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
            profile_url: "http://localhost:8083/debug/pprof/profile?seconds=5",
            liveness_url: "http://localhost:8083/check",
            readiness_url: "http://localhost:8083/check",
            memory_monitor: "fake",
            port: 4003
          ]
        ]
      ],
      [
        name: :"ex_unit_clustered_node_4@127.0.0.1",
        config: [
          autopgo: [
            autopgo_dir: "/home/user/workspace/autopgo/test/nodes/4",
            run_dir: "/home/user/workspace/autopgo/app/",
            run_command: "app --port=:8084",
            recompile_command: "go build -pgo=default.pprof -o app/app app/main.go",
            profile_url: "http://localhost:8084/debug/pprof/profile?seconds=5",
            liveness_url: "http://localhost:8084/check",
            readiness_url: "http://localhost:8084/check",
            memory_monitor: "fake",
            port: 4004
          ]
        ]
      ]
    ]
  ]

  # Define a clustered scenario
  scenario "given a healthy cluster", @opts do
    node_setup do
      Application.ensure_all_started(:swarm)
    end

    # Define a test to run in this scenario
    test "cluster has three nodes", %{cluster: c} = _context do
      [one, two, three, four] =
        Cluster.members(c)
        |> Enum.sort()

      :ok = Cluster.partition(c, [[one, two], [three], [four]])

      Cluster.call(one, fn ->
        {:ok, _pid} = Application.ensure_all_started(:autopgo)
      end)

      Cluster.call(two, fn ->
        {:ok, _pid} = Application.ensure_all_started(:autopgo)
      end)

      :timer.sleep(5000)

      [l1, l2] =
        [one, two]
        |> Enum.map(fn member ->
          {:ok, log} = Cluster.log(member)
          log
        end)

      IO.puts("Log 1: #{l1}")
      IO.puts("Log 2: #{l2}")

      [looping_controller_node, looping_controller_node] =
        [one, two]
        |> Enum.map(fn node ->
          Cluster.call(node, fn ->
            Swarm.whereis_name(:looping_controller)
            |> :erlang.node()
          end)
        end)

      assert Enum.member?([one, two], looping_controller_node)

      nodes =
        [one, two]
        |> Enum.map(fn node ->
          Cluster.call(node, fn ->
            Node.list()
          end)
        end)
        |> List.flatten()
        |> Enum.sort()

      assert nodes == [one, two]

      :ok = Cluster.stop_node(c, one)

      {node_list, looping_controller_node} =
        Cluster.call(two, fn ->
          {Node.list(), Swarm.whereis_name(:looping_controller) |> :erlang.node()}
        end)

      assert node_list == []
      assert looping_controller_node == two

      [one, two]
      |> Enum.map(fn member ->
        Cluster.log(member)
      end)
    end
  end
end
