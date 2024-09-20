defmodule Autopgo.BinaryStore do
  use GenServer

  def got_new_binary do
    GenServer.call(__MODULE__, :got_new_binary)
  end

  def get_last_binary_update(node) do
    GenServer.call({__MODULE__, node}, :get_last_binary_update)
  end

  def find_newest_binary do
    nodes = Node.list()

    if length(nodes) > 1 do
      Enum.map(nodes, fn node ->
        {Autopgo.BinaryStore.get_last_binary_update(node), node}
      end)
      |> Enum.filter(fn {datetime, _} -> datetime != nil end)
      |> Enum.max_by(&elem(&1, 0), DateTime, fn -> {:error, "No nodes have binary updated"} end)
    else
      {:error, "Not in a cluster"}
    end
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    {:ok, %{last_binary_update: nil}}
  end

  def handle_call(:get_last_binary_update, _from, %{last_binary_update: lbu} = state) do
    {:reply, lbu, state}
  end

  def handle_call(:got_new_binary, _from, state) do
    {:reply, :ok, %{state | last_binary_update: DateTime.utc_now()}}
  end
end
