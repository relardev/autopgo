defmodule Autopgo do
  def recompile(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(Autopgo.Worker, {:recompile, notify_fn})
  end

  def run_base_binary() do
    :ok = GenServer.cast(Autopgo.Worker, :run_base_binary)
  end
end

defmodule Autopgo.Worker do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Logger.info("Starting port")
    Process.flag(:trap_exit, true)
    [command | binary_args] = String.split(args.run_command)
    binary_path = Path.join(args.run_dir, command)
    :ok = File.cp(binary_path, Path.join(args.autopgo_dir, "app_backup"))

    state = %{
      autopgo_dir: args.autopgo_dir,
      binary_args: binary_args,
      run_dir: args.run_dir,
      binary_path: binary_path,
      path_of_app_to_run: binary_path,
      recompile_command: args.recompile_command,
      state: :waiting
    }

    port = open(state)
    {:ok, Map.merge(state, %{port: port})}
  end

  def handle_cast(:run_base_binary, %{state: :busy} = state) do
    Logger.info("Currentyl busy - run base binary")

    {:noreply, state}
  end

  def handle_cast(:run_base_binary, %{state: :waiting} = state) do
    Logger.info("Running base binary")

    Healthchecks.shutting_down(fn ->
      :ok = GenServer.cast(Autopgo.Worker, :readiness_checked)
    end)

    {:noreply,
     Map.merge(state, %{
       state: :busy,
       path_of_app_to_run: Path.join(state.autopgo_dir, "app_backup")
     })}
  end

  def handle_cast({:recompile, notify_fn}, %{state: :busy} = state) do
    Logger.info("Currentyl busy - recompile")
    notify_fn.({:error, "busy"})
    {:noreply, state}
  end

  def handle_cast({:recompile, notify_fn}, %{state: :waiting} = state) do
    Logger.info("Recompiling with pgo...")

    combine_profiles()

    compile(state.recompile_command)

    File.rename("default.pprof", "old.pprof")

    Healthchecks.shutting_down(fn ->
      :ok = GenServer.cast(Autopgo.Worker, :readiness_checked)
    end)

    {:noreply,
     Map.merge(state, %{notify_fn: notify_fn, state: :busy, path_of_app_to_run: state.binary_path})}
  end

  def handle_cast(:readiness_checked, state) do
    Logger.info("Readiness checked")

    # we assume 1s is enough for the lb to stop sending traffic
    Process.send_after(self(), :app_disconnected_from_lb, 1000)
    {:noreply, state}
  end

  def handle_info(:app_disconnected_from_lb, state) do
    Logger.info("App disconnected from LB")

    true = Port.close(state.port)

    port = open(state)

    Healthchecks.starting_up()

    if Map.has_key?(state, :notify_fn) do
      state.notify_fn.(:ok)
    end

    Logger.info("returning to waiting state")
    {:noreply, %{state | port: port, state: :waiting}}
  end

  def handle_info({port, :closed}, state) do
    Logger.info("Port closed")
    {:noreply, %{state | port: port}}
  end

  def handle_info({_, {:data, data}}, state) do
    # pass logs from the port to the logger
    for line <- String.split(data, "\n") do
      line = String.trim(line)

      if line != "" do
        IO.write(:stderr, "[Program]: #{line}\n")
      end
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, port, :normal}, %{port: port} = state) do
    System.stop()
    {:noreply, state}
  end

  def handle_info({:EXIT, port, :normal}, state) do
    Logger.info("Port stopped normally - #{inspect(port)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Port crashed - #{inspect(status)}")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.info("Terminating auto pgo - #{inspect(reason)}")

    try do
      Port.close(state.port)
    rescue
      _ ->
        Logger.error("Port already closed")
        :ok
    end

    :ok
  end

  defp open(state) do
    Port.open(
      {:spawn_executable, Path.join(state.autopgo_dir, "handle_stdin.sh")},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, state.run_dir},
        args: [state.path_of_app_to_run | state.binary_args]
      ]
    )
  end

  defp combine_profiles() do
    files = File.ls!("pprof/")

    profiles_files =
      files
      |> Enum.map(&Path.join(["pprof", &1]))
      |> Enum.join(" ")

    Logger.info("Combining #{Enum.count(files)} profiles")
    [command | args] = ~w(go tool pprof -proto #{profiles_files})

    {merged_profile_data, 0} = System.cmd(command, args, env: go_args())

    {:ok, fd} = File.open("default.pprof", [:write, :binary, :raw, :sync])

    :ok = IO.binwrite(fd, merged_profile_data)

    :ok = :file.datasync(fd)

    :ok = File.close(fd)
  end

  defp compile(recompile_command) do
    go_env = go_args()
    Logger.info("Compiling with args #{inspect(go_env)}")
    start_time = System.os_time(:millisecond)

    [command | args] = String.split(recompile_command)
    {_, 0} = System.cmd(command, args, env: go_env)

    Logger.info("Compiled in #{System.os_time(:millisecond) - start_time}ms")

    [command | args] = ~w(go clean -cache)
    {_, 0} = System.cmd(command, args, env: go_args())
  end

  defp go_args() do
    target =
      Autopgo.MemoryMonitor.free()
      |> (fn x -> x / 2 end).()
      |> trunc()

    [{"GOMAXPROCS", "1"}, {"GOMEMLIMIT", "#{target}MiB"}]
  end
end
