defmodule Autopgo do
  def restart(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(Autopgo.Worker, {:restart, notify_fn})
  end

  def run_base_binary() do
    :ok = GenServer.cast(Autopgo.Worker, :run_base_binary)
  end

  def write_binary(data) do
    :ok = GenServer.call(Autopgo.Worker, {:write_binary, data})
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
      state: :waiting
    }

    port = open(state)
    {:ok, Map.merge(state, %{port: port})}
  end

  def handle_call({:write_binary, data}, _from, state) do
    Logger.info("Writing new binary to #{state.binary_path}_new")
    :ok = File.write("#{state.binary_path}_new", data)
    :ok = File.chmod("#{state.binary_path}_new", 0o755)
    {:reply, :ok, state}
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

  def handle_cast({:restart, notify_fn}, %{state: :busy} = state) do
    Logger.info("Currentyl busy - restart")
    notify_fn.({:error, "busy"})
    {:noreply, state}
  end

  def handle_cast({:restart, notify_fn}, %{state: :waiting} = state) do
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

    there_is_a_new_binary = File.exists?("#{state.binary_path}_new")

    if there_is_a_new_binary do
      Logger.info("New binary found, moving it to #{state.binary_path}")
      :ok = File.rename("#{state.binary_path}_new", state.binary_path)
    end

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
end
