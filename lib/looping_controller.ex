defmodule Autopgo.LoopingController do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.send_after(self(), :tick, 5*60*1000)
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
            send(pid, :tick)
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
            Process.send_after(pid, :tick, 5*60*1000)
          {:error, _} -> 
            Logger.error("Error recompiling, stopping autopgo")
        end
      end
    )
    {:noreply, state}
  end
end
