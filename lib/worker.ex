defmodule Autopgo.Worker do
  use GenServer

  require Logger

  @graceful_shutdown_signal "-15"
  @kill_signal "-9"

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.flag(:trap_exit, true)
    [command | binary_args] = String.split(args.run_command)
    binary_path = Path.join(args.run_dir, command)
    File.exists?(binary_path) || raise("your program not found under: #{binary_path}")
    backup_path = Path.join(args.autopgo_dir, "app_backup")
    File.cp!(binary_path, backup_path)

    handle_stdin_path = Path.join(args.autopgo_dir, "handle_stdin.sh")

    File.exists?(handle_stdin_path) ||
      raise(
        "handle_stdin.sh not found under: #{handle_stdin_path}, most likeliy autopgo_path is wrong"
      )

    ip =
      Node.self()
      |> Atom.to_string()
      |> String.split("@")
      |> List.last()

    state = %{
      retry_check_for_binary_minutes: 15,
      autopgo_dir: args.autopgo_dir,
      binary_args: binary_args,
      run_dir: args.run_dir,
      binary_path: binary_path,
      path_of_app_to_run: binary_path,
      handle_stdin_path: handle_stdin_path,
      state: :waiting,
      pid: nil,
      ip: ip
    }

    if args.pull_binary_on_init do
      result = get_binray_if_available(state)

      if result == :error do
        Process.send_after(self(), :update_binary, 5 * 60 * 1000)
      end
    end

    Logger.info("Starting port worker")
    port = open(state)
    Logger.info("Port worker started - #{inspect(port)}")

    {:ok, Map.merge(state, %{port: port})}
  end

  def handle_call({:write_binary, data}, _from, state) do
    Logger.info("Writing new binary to #{state.binary_path}_new")
    :ok = File.write("#{state.binary_path}_new", data)
    :ok = File.chmod("#{state.binary_path}_new", 0o755)
    {:reply, :ok, state}
  end

  def handle_call({:read_binary, destination_stream}, _from, state) do
    Logger.info("Reading binary from #{state.binary_path}")

    try do
      source_stream = File.stream!(state.binary_path, 2048)
      Enum.into(source_stream, destination_stream)
      {:reply, :ok, state}
    catch
      e ->
        Logger.error("Failed to read binary - #{inspect(e)}")
        {:reply, :error, state}
    end
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

    state = port_close(state)

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
    pid =
      for line <- String.split(data, "\n") do
        line = String.trim(line)

        case line do
          <<"PID:xetw:", pid::binary>> ->
            Logger.info("got pid: #{pid}")
            pid

          "" ->
            nil

          _ ->
            IO.write(:stderr, "program@#{state.ip} | #{line}\n")
            nil
        end
      end
      |> Enum.find(&(&1 != nil))

    pid = if pid != nil, do: String.trim(pid), else: state.pid

    {:noreply, %{state | pid: pid}}
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

  def handle_info(:update_binary, state) do
    next_profile = Autopgo.LoopingController.next_profile_at()
    diff = DateTime.diff(next_profile, DateTime.utc_now(), :minute)

    if diff > state.retry_check_for_binary_minutes do
      Logger.info("Profile in more than 15 min, checking for new binary")

      if get_binray_if_available(state) == :ok do
        Autopgo.restart()
      end
    else
      Logger.info("Profile in less than 15 min, not checking for new binary")
    end

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
    there_is_a_new_binary = File.exists?("#{state.binary_path}_new")

    if there_is_a_new_binary do
      Logger.info("New binary found, moving it to #{state.binary_path}")
      :ok = File.rename("#{state.binary_path}_new", state.binary_path)
      Autopgo.BinaryStore.got_new_binary()
    end

    Port.open(
      {:spawn_executable, state.handle_stdin_path},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, state.run_dir},
        args: [state.path_of_app_to_run | state.binary_args]
      ]
    )
  end

  defp port_close(state) do
    Logger.info("Closing port: #{inspect(state.port)}, pid: #{state.pid}")

    System.cmd("kill", [@graceful_shutdown_signal, state.pid])

    port = state.port

    receive do
      {^port, {:exit_status, 0}} ->
        Logger.info("Port closed successfully")
    after
      60_000 ->
        Logger.error("Port did not close in 60s, force killing it")
        System.cmd("kill", [@kill_signal, state.pid])
    end

    %{
      state
      | port: nil,
        pid: nil
    }
  end

  defp get_binray_if_available(state) do
    file_path = "#{state.binary_path}_new"

    with {:ok, node} <-
           Autopgo.BinaryStore.find_newest_binary() |> Context.add("No new binary found"),
         :ok <- Autopgo.read_binary(node, file_path) do
      :ok
    else
      {:error, reason} ->
        Logger.info(reason)
        :error
    end
  end
end

defmodule Context do
  def add(result, context) do
    case result do
      {:error, reason} ->
        {:error, "#{context}: #{reason}"}

      _ ->
        result
    end
  end
end
