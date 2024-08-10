defmodule Autopgo.WebController do
  use GenServer

  require Logger

  def run_with_pgo do
    GenServer.cast(__MODULE__, :run_with_pgo)
  end

  def run_base_binary do
    GenServer.cast(__MODULE__, :run_base_binary)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, args}
  end

  def handle_cast(:run_base_binary, state) do
    Autopgo.run_base_binary()
    {:noreply, state}
  end

  def handle_cast(:run_with_pgo, state) do
    pid = self()
    Autopgo.gather_profile(
      fn x -> 
        case x do
          :ok -> 
            send(pid, :recompile)
          {:error, _} -> 
            Logger.error("Error gathering profile")
        end
      end
    )
    {:noreply, state}
  end

  def handle_info(:recompile, state) do
    Autopgo.recompile()
    {:noreply, state}
  end
end
