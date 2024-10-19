defmodule Autopgo.Worker do
  use GenServer

  require Logger

  def restart_all(notify_fn) do
    Logger.info("Restarting autopgo on ALL nodes")
    GenServer.abcast(__MODULE__, {:restart, notify_fn})
  end

  def restart(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(__MODULE__, {:restart, notify_fn})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{state: :waiting, notify_fn: nil}}
  end

  def handle_cast({:restart, notify_fn}, state) do
    self = self()

    Healthchecks.shutting_down(fn ->
      send(self, :readiness_checked)
    end)

    receive do
      :readiness_checked ->
        Logger.info("Readiness checked")
    end

    # wait for lb to disconnect
    :timer.sleep(1000)

    Logger.info("App disconnected from LB")

    Autopgo.AppSupervisor.restart()

    Healthchecks.starting_up()

    notify_fn.(:ok)

    Logger.info("Done restarting")
    drain_restarts_in_queue()
    {:noreply, state}
  end

  def drain_restarts_in_queue() do
    receive do
      {:restart, notify_fn} ->
        notify_fn.({:error, "was busy"})
        drain_restarts_in_queue()
    after
      0 -> :ok
    end
  end
end
