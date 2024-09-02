defmodule Autopgo.LoopingController do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.send_after(self(), :tick, args.retry_interval_ms)
    now = DateTime.utc_now()
    initial_profile_at = DateTime.add(now, args.initial_profile_delay_seconds)
    {:ok, %{
      start: now, 
      next_profile_at: initial_profile_at, 
      recompile_interval_seconds: args.recompile_interval_seconds, 
      retry_interval_ms: args.retry_interval_ms,
      machine_state: :waiting
    }}
  end

  def handle_info(:tick, %{machine_state: :busy} = state) do
    Logger.info("Controller is busy, IF THIS HAPPENS INVESTIGATE")
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    Logger.info("Controller tick")
    machine_state = if DateTime.compare(DateTime.utc_now(), state.next_profile_at) == :gt do
      ask_for_profile()
      :busy
    else
      Process.send_after(self(), :tick, state.retry_interval_ms)
      :waiting
    end
    {:noreply, %{state | machine_state: machine_state}}
  end

  def handle_info(:retry_profile, state) do
    Logger.info("Retrying profile gather")
    ask_for_profile()
    {:noreply, %{state | machine_state: :waiting}}
  end

  def handle_info(:profile_gathered, state) do
    pid = self()
    Autopgo.recompile(
      fn x -> 
        case x do
          :ok -> 
            Process.send_after(pid, :done, state.retry_interval_ms)
          {:error, _} -> 
            Logger.error("Error recompiling, stopping autopgo")
        end
      end
    )
    {:noreply, %{state | machine_state: :busy}}
  end

  def handle_info(:done, state) do
    Logger.info("Recompile done, resuming controller")
    Process.send_after(self(), :tick, state.retry_interval_ms)
    next_profile_at = DateTime.add(DateTime.utc_now(), state.recompile_interval_seconds)
    {:noreply, %{state | machine_state: :waiting, next_profile_at: next_profile_at}}
  end

  def handle_call({:swarm, :begin_handoff}, _from, state) do
    Logger.info("Handoff initiated for #{Node.self()}")
    {:reply, {:resume, state}, state}
  end

  def handle_cast({:swarm, :end_handoff, _handedoff_state}, %{machine_state: :busy} = state) do
    Logger.info("Handoff while busy, keeping state for #{Node.self()}")
    {:noreply, state}
  end

  def handle_cast({:swarm, :end_handoff, handedoff_state}, state) do
    new_state = if handedoff_state.start > state.start do
      handedoff_state
    else
      state
    end

    Logger.info("Handoff completed for #{Node.self()}")
    {:noreply, %{new_state | machine_state: :waiting}}
  end

  defp ask_for_profile do
    pid = self()
    Autopgo.gather_profile(
      fn x -> 
        case x do
          :ok -> 
            send(pid, :profile_gathered)
          {:error, _} -> 
            Logger.error("Controller got error gathering profile")
            Process.send_after(pid, :retry_profile, 1000)
        end
      end
    )
  end
end
