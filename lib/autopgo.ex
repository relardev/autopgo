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
    port = Port.open({:spawn, args.binary_path}, [:binary, :exit_status])
    {:ok, Map.merge(args, %{port: port, state: :waiting})}
  end

  def handle_cast({:gather_profile, notify_fn}, state) do
    Logger.info("Gathering profile")
    case Healthchecks.readiness() do
      :ok -> 
        timestamp = System.os_time(:second)
        [command | args]  = ~w(wget -O pprof/#{timestamp}.pprof #{state.profile_url})

        {_, 0} = System.cmd(command, args)

        Logger.info("Profile gathered")
        notify_fn.(:ok)

        {:noreply, state}
      {:error, _} -> 
        notify_fn.({:error, "readiness check failed"})
        {:noreply, state}
    end
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

    {:ok, fd} = File.open("default.pprof", [:write, :binary, :raw])

    IO.binwrite(fd, merged_profile_data)

    File.close(fd)

    Logger.info("Compiling")
    start_time = System.os_time(:millisecond)
    [command | args] = String.split(state.recompile_command)

    {_, 0} = System.cmd(command, args, env: [{"GOMAXPROCS", "1"}])

    Logger.info("Compiled in #{System.os_time(:millisecond) - start_time}ms")

    File.rm_rf("default.pprof")

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

    stop_port(state.port)
    {:noreply, state}
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

  def handle_info({_, {:exit_status, status}}, state) do
    Logger.info("Port exited with status #{status}, restarting...")

    port = Port.open({:spawn, state.binary_path}, [:binary, :exit_status])
    Healthchecks.starting_up()

    state.notify_fn.(:ok)

    {:noreply, %{state | port: port, state: :waiting}}
  end

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  defp stop_port(port) do
    Logger.info("Stopping port")
    pid = Port.info(port)[:os_pid]
    
    # send terminate signal to the port
    # this is hack to not require the runned process to handle
    # stdin eof
    System.cmd("kill", ["15", "#{pid}"])
  end

  def terminate(_reason, state) do
    Logger.info("Terminating auto pgo")
    :ok
  end
end
