defmodule Autopgo do
  def gather_profile(notify_fn \\ fn _ -> :ok end) do
    GenServer.cast(Autopgo.Worker, {:gather_profile, notify_fn})
  end

  def recompile(notify_fn \\ fn _ -> :ok end) do
    GenServer.cast(Autopgo.Worker, {:recompile, notify_fn})
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
    port = open(args.binary_path)
    {:ok, Map.merge(args, %{port: port, state: :waiting})}
  end

  def handle_cast({:gather_profile, notify_fn}, state) do
    Logger.info("Gathering profile")
    case ProfileManager.new_profile(state.profile_url) do
      :ok -> 
        notify_fn.(:ok)
      {:error, _} -> 
        notify_fn.({:error, "profile gathering failed"})
    end
    {:noreply, state}
  end

  def handle_cast({:recompile, notify_fn}, %{state: :compiling} = state) do
    Logger.info("Already compiling")
    notify_fn.({:error, "already compiling"})
    {:noreply, state}
  end

  def handle_cast({:recompile, notify_fn}, %{state: :waiting} = state) do
    Logger.info("Recompiling...")

   files = File.ls!("pprof/")

    profiles_files = 
      files
    |> Enum.map(&Path.join(["pprof", &1]))
    |> Enum.join(" ")

    Logger.info("Combining #{Enum.count(files)} profiles")
    [command | args ] = ~w(go tool pprof -proto #{profiles_files})

    {merged_profile_data, 0} = System.cmd(command, args, env: [{"GOMAXPROCS", "1"}])

    {:ok, fd} = File.open("default.pprof", [:write, :binary, :raw, :sync])

    IO.binwrite(fd, merged_profile_data)

    :file.datasync(fd)

    File.close(fd)

    Logger.info("Compiling")
    start_time = System.os_time(:millisecond)
    [command | args] = String.split(state.recompile_command)

    {_, 0} = System.cmd(command, args, env: [{"GOMAXPROCS", "1"}])

    Logger.info("Compiled in #{System.os_time(:millisecond) - start_time}ms")

    File.rename("default.pprof", "old.pprof")

    Healthchecks.shutting_down(fn -> 
      GenServer.cast(Autopgo.Worker, :readiness_checked) 
    end)

    {:noreply, Map.merge(state, %{notify_fn: notify_fn, state: :compiling})}
  end

  def handle_cast(:readiness_checked, state) do
    Logger.info("Readiness checked")

    # we assume 1s is enough for the lb to stop sending traffic
    Process.send_after(self(), :app_disconnected_from_lb, 1000)
    {:noreply, state}
  end

  def handle_info(:app_disconnected_from_lb, state) do
    Logger.info("App disconnected from LB")

    Port.close(state.port)

    port = open(state.binary_path)

    Healthchecks.starting_up()

    state.notify_fn.(:ok)

    {:noreply, %{state | port: port, state: :waiting}}
  end

  def handle_info({port, :closed}, state) do
    Logger.info("Port closed")
    {:noreply, %{state | port: port}}
  end

  def handle_info({_, {:data, data}}, state) do
    # pass logs from the port to the logger
    Logger.info("Port: #{data}")
    {:noreply, state}
  end

  def handle_info({:EXIT, port, :normal}, %{port: port} = state) do
    System.stop()
    {:noreply, state}
  end

  def handle_info({:EXIT, _port, :normal}, state) do
    Logger.info("Port stopped normally")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _status}}, %{port: port} = state) do
    Logger.info("Port crashed")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  def terminate(_reason, state) do
    Logger.info("Terminating auto pgo")
    Port.close(state.port)
    :ok
  end

  defp open(path, args \\ []) do
    Port.open(
      {:spawn_executable, "./handle_stdin.sh"},
      [:binary, :exit_status, args: [path | args]]
    )
  end
end
