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
            fake_memory_monitor: true,
            port: 4001
          ],
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
            fake_memory_monitor: true,
            port: 4002
          ],
        ]
      ]
    ]
  ]


  # Define a clustered scenario
  scenario "given a healthy cluster", @opts do

    setup %{cluster: c} do
      Cluster.map(c, fn -> 
        Application.ensure_all_started(:swarm)
        Application.ensure_all_started(:autopgo)
      end)
      |> dbg()
      :ok
    end

    # Define a test to run in this scenario
    test "cluster has three nodes", %{cluster: c} = _context do
      Cluster.members(c)
      |> Enum.map(&Cluster.log(&1))
      |> dbg()
      looping_controller = Cluster.map(c, Node, :list, [])
      dbg(looping_controller)
      assert length(Cluster.members(c)) == 2
    end
  end
end
