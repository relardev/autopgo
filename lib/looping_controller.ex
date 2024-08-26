defmodule Autopgo.LoopingController do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.send_after(self(), :tick, args.initial_profile_delay)
    {:ok, args}
  end

  def handle_info(:tick, state) do
    pid = self()
    Autopgo.gather_profile(
      fn x -> 
        case x do
          :ok -> 
            send(pid, :profile_gathered)
          {:error, _} -> 
            Process.send_after(pid, :tick, state.retry_interval)
        end
      end
    )
    {:noreply, state}
  end

  def handle_info(:profile_gathered, state) do
    pid = self()
    Autopgo.recompile(
      fn x -> 
        case x do
          :ok -> 
            Process.send_after(pid, :tick, state.recompile_interval)
          {:error, _} -> 
            Logger.error("Error recompiling, stopping autopgo")
        end
      end
    )
    {:noreply, state}
  end

  def handle_call({:swarm, :begin_handoff}, _from, state) do
    Logger.info("Handoff initiated for #{Node.self()}")
    {:reply, {:resume, state}, state}
  end

  def handle_cast({:swarm, :end_handoff, handedoff_state}, _state) do
    Logger.info("Handoff completed for #{Node.self()}")
    {:noreply, handedoff_state}
  end
end
