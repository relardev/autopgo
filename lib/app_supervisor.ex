defmodule Autopgo.AppSupervisor do
  use GenServer

  require Logger

  @graceful_shutdown_signal "-15"
  @kill_signal "-9"

  def restart() do
    GenServer.call(__MODULE__, :restart, 65_000)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.flag(:trap_exit, true)
    [_ | binary_args] = String.split(args.run_command)
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
      autopgo_dir: args.autopgo_dir,
      binary_args: binary_args,
      run_dir: args.run_dir,
      handle_stdin_path: handle_stdin_path,
      pid: nil,
      ip: ip
    }

    Logger.info("Starting port worker")
    port = open(state)
    Logger.info("Port worker started - #{inspect(port)}")
    {:ok, Map.merge(state, %{port: port})}
  end

  def handle_call(:restart, _from, state) do
    state = port_close(state)

    port = open(state)
    {:reply, :ok, %{state | port: port}}
  end

  def handle_info({_port, :closed}, state) do
    Logger.info("Port closed")
    {:noreply, state}
  end

  def handle_info({_, {:data, data}}, state) do
    pid = handle_stdin(data, state.ip)
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

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  defp open(state) do
    binary_path = Autopgo.BinaryStore.binary_path()

    Port.open(
      {:spawn_executable, state.handle_stdin_path},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, state.run_dir},
        args: [binary_path | state.binary_args]
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

  defp handle_stdin(data, ip) do
    for line <- String.split(data, "\n") do
      line = String.trim(line)

      case line do
        <<"PID:xetw:", pid::binary>> ->
          Logger.info("got pid: #{pid}")
          pid

        "" ->
          nil

        _ ->
          IO.write(:stderr, "program@#{ip} | #{line}\n")
          nil
      end
    end
    |> Enum.find(&(&1 != nil))
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
end
