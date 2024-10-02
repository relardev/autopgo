defmodule Autopgo.Worker do
  use GenServer

  require Logger

  def restart(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(__MODULE__, {:restart, notify_fn})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{state: :waiting, notify_fn: nil}}
  end

  def handle_cast({:restart, notify_fn}, %{state: :busy} = state) do
    Logger.info("Currentyl busy - restart")
    notify_fn.({:error, "busy"})
    {:noreply, state}
  end

  def handle_cast({:restart, notify_fn}, %{state: :waiting} = state) do
    Healthchecks.shutting_down(fn ->
      :ok = GenServer.cast(Autopgo.Worker, :readiness_checked)
    end)

    {:noreply, Map.merge(state, %{notify_fn: notify_fn, state: :busy})}
  end

  def handle_cast(:readiness_checked, state) do
    Logger.info("Readiness checked")

    # we assume 1s is enough for the lb to stop sending traffic
    Process.send_after(self(), :app_disconnected_from_lb, 1000)
    {:noreply, state}
  end

  def handle_info(:app_disconnected_from_lb, state) do
    Logger.info("App disconnected from LB")

    Autopgo.AppSupervisor.restart()

    Healthchecks.starting_up()

    if Map.has_key?(state, :notify_fn) do
      state.notify_fn.(:ok)
    end

    Logger.info("returning to waiting state")
    {:noreply, %{state | state: :waiting}}
  end
end
