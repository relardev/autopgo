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
    boot_timeout: 10_000,
    capture_log: true,
    nodes: [
      [
        name: :"ex_unit_clustered_node_1@127.0.0.1",
        config: [
          autopgo: [
            fake_memory_monitor: true,
            port: 4001
          ],
        ]
      ],
      [
        name: :"ex_unit_clustered_node_2@127.0.0.1",
        config: [
          autopgo: [
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
        env = Application.get_all_env(:autopgo)
        IO.inspect(env)
        res = Application.ensure_all_started([:swarm, :autopgo])
        IO.inspect(res)
        res
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
