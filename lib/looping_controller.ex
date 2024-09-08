defmodule Autopgo.LoopingController do
  use Watchdog.SingletonGenServer

  require Logger

  def initial_state do
    now = DateTime.utc_now()
    next_profile_at = DateTime.add(now, 10)

    run_dir = Application.get_env(:autopgo, :run_dir)
    run_command = Application.get_env(:autopgo, :run_command)
    [command | _] = String.split(run_command)
    binary_path = Path.join(run_dir, command)

    %{
      start: now,
      next_profile_at: next_profile_at,
      compile_command: Application.get_env(:autopgo, :recompile_command),
      binary_path: binary_path,
      recompile_interval_seconds: 60,
      retry_interval_ms: 1000,
      tick_ms: 5000,
      machine_state: :waiting,
      restarts_remaining: 0,
      restart_timer_cancel: nil
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
    {:noreply, state}
  end

  def handle_info(:profile_gathered, state) do
    Logger.info("Profile gathered, compiling the app")

    Autopgo.Compiler.compile(state.compile_command)

    File.cp!(state.binary_path, "#{state.binary_path}_new")

    Logger.info("Compiling done, distributing the binary")

    data = File.read!(state.binary_path)

    Enum.each(Node.list(), fn node ->
      Logger.info("Distributing binary to #{node}")
      :rpc.call(node, Autopgo, :write_binary, [data])
    end)

    self = self()

    restart_callback = fn x ->
      case x do
        :ok ->
          send(self, :restarted)

        {:error, _} ->
          Logger.error("Error restarting")
      end
    end

    nodes = [Node.self() | Node.list()]

    Enum.each(nodes, fn node ->
      Logger.info("Restarting autopgo on #{node}")
      :rpc.call(node, Autopgo, :restart, [restart_callback])
    end)

    timer_cancel = Process.send_after(self(), :done, 60 * 1000)

    {:noreply,
     %{
       state
       | machine_state: :busy,
         restarts_remaining: length(nodes),
         restart_timer_cancel: timer_cancel
     }}
  end

  def handle_info(:restarted, state) do
    restarts_remaining = state.restarts_remaining - 1
    Logger.info("Restarted, waiting for #{state.restarts_remaining} more")

    if restarts_remaining == 0 do
      Process.cancel_timer(state.restart_timer_cancel)
      send(self(), :done)
    end

    {:noreply, %{state | restarts_remaining: restarts_remaining}}
  end

  def handle_info(:done, %{machine_state: :waiting} = state) do
    Logger.info("Got done while wasnt expecting, INVESTIGATE")
    {:noreply, state}
  end

  def handle_info(:done, %{machine_state: :busy} = state) do
    Logger.info("Restart done, resuming ticking")
    Process.send_after(self(), :tick, state.retry_interval_ms)
    next_profile_at = DateTime.add(DateTime.utc_now(), state.recompile_interval_seconds)
    {:noreply, %{state | machine_state: :waiting, next_profile_at: next_profile_at}}
  end

  def handle_info({:EXIT, _port, :normal}, state) do
    {:noreply, state}
  end

  defp ask_for_profile do
    pid = self()

    Autopgo.ProfileManager.gather_profiles(fn ->
      send(pid, :profile_gathered)
    end)
  end
end
