defmodule Autopgo.LoopingControllerWatchdog do
  use Watchdog.SingletonGenServer

  require Logger

  def initial_state do
    now = DateTime.utc_now()
    next_profile_at = DateTime.add(now, 10)

    %{
      start: now,
      next_profile_at: next_profile_at,
      recompile_interval_seconds: 60,
      retry_interval_ms: 1000,
      tick_ms: 5000,
      machine_state: :waiting
    }
  end

  def setup(state, _meta) do
    Process.send_after(self(), :tick, state.tick_ms)
    {:ok, state}
  end

  def import_state(_initial_state, import_state) do
    %{import_state | machine_state: :waiting}
  end

  def handle_info(:tick, %{machine_state: :busy} = state) do
    Logger.info("Controller is busy, IF THIS HAPPENS INVESTIGATE")
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    Logger.info(
      "Controller tick, started: #{state.start}, next_profile_at: #{state.next_profile_at}"
    )

    machine_state =
      if DateTime.compare(DateTime.utc_now(), state.next_profile_at) == :gt do
        ask_for_profile()
        :busy
      else
        Process.send_after(self(), :tick, state.tick_ms)
        :waiting
      end

    {:noreply, %{state | machine_state: machine_state}}
  end

  def handle_info(:retry_profile, state) do
    Logger.info("Retrying profile gather")
    ask_for_profile()
    {:noreply, %{state | machine_state: :busy}}
  end

  def handle_info(:profile_gathered, state) do
    pid = self()

    Autopgo.recompile(fn x ->
      case x do
        :ok ->
          Process.send_after(pid, :done, state.retry_interval_ms)

        {:error, _} ->
          Logger.error("Error recompiling, stopping autopgo")
      end
    end)

    {:noreply, %{state | machine_state: :busy}}
  end

  def handle_info(:done, state) do
    Logger.info("Recompile done, resuming controller")
    Process.send_after(self(), :tick, state.retry_interval_ms)
    next_profile_at = DateTime.add(DateTime.utc_now(), state.recompile_interval_seconds)
    {:noreply, %{state | machine_state: :waiting, next_profile_at: next_profile_at}}
  end

  defp ask_for_profile do
    pid = self()

    Autopgo.ProfileManager.gather_profiles(fn ->
      send(pid, :profile_gathered)
    end)
  end
end
