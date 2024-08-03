defmodule Healthchecks do
  use GenServer

  require Logger

  def liveness do
    GenServer.call(__MODULE__, :liveness)
  end

  def readiness do
    GenServer.call(__MODULE__, :readiness)
  end

  def shutting_down(notify_fn) do
    GenServer.call(__MODULE__, {:mode, :shutting_down, notify_fn})
  end

  def starting_up() do
    GenServer.call(__MODULE__, {:mode, :starting_up})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, Map.merge(args, %{mode: :normal})}
  end

  def handle_call(:liveness, _from, %{mode: :normal} = state) do
    case check_endpoint(state.liveness_url) do
      :ok -> {:reply, :ok, state}
      {:error, _} -> {:reply, {:error, "liveness check failed"}, state}
    end
  end

  def handle_call(:readiness, _from, %{mode: :normal} = state) do
    case check_endpoint(state.readiness_url) do
      :ok -> {:reply, :ok, state}
      {:error, _} -> {:reply, {:error, "readiness check failed - not started yet"}, state}
    end
  end

  def handle_call({:mode, :shutting_down, notify_fn}, _from, state) do
    Logger.info("Healthchecks mode: shutting down")
    {:reply, :ok, Map.merge(state, %{mode: :shutting_down, notify_fn: notify_fn})}
  end

  def handle_call(:liveness, _from, %{mode: :shutting_down} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:readiness, _from, %{mode: :shutting_down} = state) do
    state.notify_fn.()
    {:reply, {:error, "readiness check failed - shutting down"}, %{state | notify_fn: &no_notify_fn/0}}
  end

  def handle_call({:mode, :starting_up}, _from, state) do
    Logger.info("Healthchecks mode: starting up")
    Process.send_after(self(), :check_if_ready, 1000)
    {:reply, :ok, Map.put(state, :mode, :starting_up)}
  end

  def handle_call(:liveness, _from, %{mode: :starting_up} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:readiness, _from, %{mode: :starting_up} = state) do
    {:reply, {:error, "readiness check failed - starting up"}, state}
  end

  def handle_info(:check_if_ready, %{mode: :starting_up} = state) do
    case check_endpoint(state.readiness_url) do
      :ok -> 
        Logger.info("Healthchecks: readiness passed, going back to normal mode")
        {:noreply, Map.put(state, :mode, :normal)}
      {:error, _} -> 
        Logger.info("Still not ready")
        Process.send_after(self(), :check_if_ready, 1000)
        {:noreply, state}
    end
  end

  defp no_notify_fn(), do: :ok

  defp check_endpoint(url) do
    with {:ok, resp} <- Req.get(url, max_retries: 0),
         200 <- resp.status
    do 
      :ok
    else
      _ -> {:error, "check failed"}
    end
  end
end
