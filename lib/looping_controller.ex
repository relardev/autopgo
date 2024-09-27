defmodule Autopgo.LoopingController do
  use Watchdog.SingletonGenServer

  require Logger

  def initial_state do
    now = DateTime.utc_now()
    first_profile_in_seconds = Application.get_env(:autopgo, :first_profile_in_seconds, 7 * 60)
    next_profile_at = DateTime.add(now, first_profile_in_seconds)

    tick_ms = Application.get_env(:autopgo, :tick_ms, 60 * 1000)

    recompile_interval_seconds =
      Application.get_env(:autopgo, :recompile_interval_seconds, 60 * 60)

    %{
      start: now,
      next_profile_at: next_profile_at,
      recompile_interval_seconds: recompile_interval_seconds,
      retry_interval_ms: 1000,
      tick_ms: tick_ms,
      machine_state: :waiting,
      restarts_remaining: 0,
      restart_timer_cancel: nil,
      compile_task: nil
    }
  end

  def setup(state, _meta) do
    Process.send_after(self(), :tick, state.tick_ms)
    {:ok, state}
  end

  def import_state(_initial_state, import_state) do
    %{import_state | machine_state: :waiting}
  end

  def next_profile_at do
    GenServer.call({:global, __MODULE__}, :next_profile_at)
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

    task = compile()

    {:noreply, %{state | compile_task: task}}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, %{compile_task: %Task{ref: ref}} = state) do
    Logger.info("TASK DONE, but it was DEMONITORED, INVESTIGATE")
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, :noconnection},
        %{compile_task: %Task{ref: ref}} = state
      ) do
    Logger.info("Node died during compilation, retrying")

    task = compile()

    {:noreply, %{state | compile_task: task}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{compile_task: %Task{ref: ref}} = state) do
    Logger.info("Compilation failed: #{inspect(reason)}, stopping autopgo")
    {:noreply, state}
  end

  def handle_info({ref, :ok}, %{compile_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

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

  # We started second compilation and then netsplit healed
  def handle_info({_ref, :ok}, state) do
    Logger.info("Compilation done, but we were not expecting it, INVESTIGATE")
    {:noreply, state}
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

  def handle_call(:next_profile_at, _from, state) do
    {:reply, state.next_profile_at, state}
  end

  defp ask_for_profile do
    pid = self()

    Autopgo.ProfileManager.gather_profiles(fn ->
      send(pid, :profile_gathered)
    end)
  end

  defp compile() do
    node = select_node()
    Logger.info("Compiling on #{node}")

    Autopgo.ProfileManager.send_profile(node)

    Task.Supervisor.async_nolink(
      {Autopgo.Compilation.TaskSupervisor, node},
      Autopgo.GoCompiler,
      :compile_and_distribute,
      []
    )
  end

  defp select_node() do
    nodes = [Node.self() | Node.list()]

    {node, free_mem} =
      Enum.map(nodes, fn node ->
        {
          node,
          :rpc.call(node, Autopgo.MemoryMonitor, :free, [])
        }
      end)
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.reverse()
      |> hd()

    Logger.info("Selected node: #{inspect(node)}, free mem: #{inspect(free_mem)}")

    node
  end
end
