defmodule Autopgo.LoopingController do
  use GenServer

  require Logger

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    Logger.info("Initializing state")
    Process.flag(:trap_exit, true)
    now = DateTime.utc_now()
    first_profile_in_seconds = Application.get_env(:autopgo, :first_profile_in_seconds, 7 * 60)
    next_profile_at = DateTime.add(now, first_profile_in_seconds)

    tick_ms = Application.get_env(:autopgo, :tick_ms, 60 * 1000)

    recompile_interval_seconds =
      Application.get_env(:autopgo, :recompile_interval_seconds, 60 * 60)

    Process.send_after(self(), :tick, tick_ms)

    {:ok,
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
     }}
  end

  def terminate(_reason, state) do
    # TODO

    Highlander.pid(__MODULE__)
    |> GenServer.cast({:merge_state, state})

    Logger.info("Terminating LoopingController at node: #{Node.self()}, sedning state to ")
    :ok
  end

  def next_profile_at(pid) do
    GenServer.call(pid, :next_profile_at)
  end

  def handle_cast({:merge_state, other_state}, state) do
    state = select_state(state, other_state)
    {:noreply, state}
  end

  def handle_info(:tick, %{machine_state: :busy} = state) do
    Logger.info("Controller is busy, IF THIS HAPPENS INVESTIGATE")
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    formatted_next = Calendar.strftime(state.next_profile_at, "%H:%M:%S")
    formatted_start = Calendar.strftime(state.start, "%Y-%m-%d %H:%M:%S")
    Logger.info("Tick, started: #{formatted_start}, next: #{formatted_next}")

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

  def handle_info(
        {:DOWN, ref, :process, _pid, :shutdown},
        %{compile_task: %Task{ref: ref}} = state
      ) do
    Logger.info("Compilation failed, with :shutdown, retrying")

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

        {:error, reason} ->
          Logger.error("Error restarting - #{inspect(reason)}")
      end
    end

    Autopgo.Worker.restart_all(restart_callback)

    timer_cancel = Process.send_after(self(), :done, 60 * 1000)

    nodes = [Node.self() | Node.list()]

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
    node = Autopgo.MemoryMonitor.select_node_with_lowest_memory_usage()
    Logger.info("Compiling on #{node}")

    Autopgo.ProfileManager.send_profile(node)

    Task.Supervisor.async_nolink(
      {Autopgo.Compilation.TaskSupervisor, node},
      Autopgo.GoCompiler,
      :compile_and_distribute,
      []
    )
  end

  defp select_state(state1, state2) do
    if DateTime.compare(state1.start, state2.start) == :lt do
      Logger.info("Selecting earlier state")
      state1
    else
      Logger.info("Selecting later state")
      state2
    end
  end
end
