defmodule Autopgo.ProfileManager do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok,
     %{
       url: args.url,
       generation: 0,
       machine_state: :waiting,
       callback: nil,
       timer_cancel: nil
     }}
  end

  def gather_profiles(callback) do
    GenServer.call(__MODULE__, {:gather_profiles, callback})
  end

  def handle_call({:gather_profiles, _callback}, _from, %{machine_state: :gathering} = state),
    do: {:reply, {:error, "busy"}, state}

  def handle_call({:gather_profiles, callback}, _from, state) do
    nodes = [Node.self() | Node.list()]

    nodes
    |> Enum.each(fn node ->
      GenServer.cast({__MODULE__, node}, {:new_profile, self()})
    end)

    timer_cancel = Process.send_after(self(), :done, 35 * 1000)

    {:reply, :ok,
     %{
       state
       | machine_state: :gathering,
         timer_cancel: timer_cancel,
         callback: callback
     }}
  end

  def handle_cast({:new_profile, to}, state) do
    new_profile(state.url, to, 0)
    {:noreply, state}
  end

  defp new_profile(_, to, 10), do: send(to, {:new_profile_error, "Failed to download pprof file"})

  defp new_profile(url, to, count) do
    case Healthchecks.readiness() do
      :ok ->
        File.ls!("pprof") |> Enum.each(fn x -> File.rm(Path.join(["pprof", x])) end)

        result = Req.get!(url)

        Logger.info("New profile from #{Node.self()}")
        send(to, {:gathered_profile, result, Node.self()})

      {:error, _} ->
        :timer.sleep(2000)
        new_profile(url, to, count + 1)
    end
  end

  def handle_info(:done, %{machine_state: :waiting} = state) do
    Logger.error("Got 'done' but was not expecting it")
    {:noreply, state}
  end

  def handle_info(:done, state) do
    Process.cancel_timer(state.timer_cancel)
    state.callback.()
    {:noreply, %{state | machine_state: :waiting}}
  end

  def handle_info({:gathered_profile, result, from}, state) do
    Logger.info("Gathered profile from #{from}")
    timestamp = System.os_time(:second)
    :ok = File.write!("pprof/#{timestamp}_#{from}.pprof", result.body)
    {:noreply, state}
  end
end
