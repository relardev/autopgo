defmodule Autopgo do
  def gather_profile do
    GenServer.cast(Autopgo.Worker, :gather_profile)
  end
  def recompile do
    GenServer.cast(Autopgo.Worker, :recompile)
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
    port = Port.open({:spawn, args.binary_path}, [:binary, :exit_status])
    {:ok, Map.merge(args, %{port: port})}
  end

  def handle_cast(:gather_profile, state) do
    Logger.info("Gathering profile")
    timestamp = System.os_time(:second)
    [command | args]  = ~w(wget -O pprof/#{timestamp}.pprof #{state.profile_url})

    {_, 0} = System.cmd(command, args)

    Logger.info("Profile gathered")

    {:noreply, state}
  end

  def handle_cast(:recompile, state) do
    Logger.info("Recompiling...")

   files = File.ls!("pprof/")

    profiles_files = 
      files
    |> Enum.map(&Path.join(["pprof", &1]))
    |> Enum.join(" ")

    Logger.info("Combining #{Enum.count(files)} profiles")
    [command | args ] = ~w(go tool pprof -proto #{profiles_files})

    {merged_profile_data, 0} = System.cmd(command, args, env: [{"GOMAXPROCS", "1"}])

    File.write!("default.pprof", merged_profile_data)

    Logger.info("Compiling")
    start_time = System.os_time(:millisecond)
    [command | args] = String.split(state.recompile_command)
    {_, 0} = System.cmd(command, args, env: [{"GOMAXPROCS", "1"}])

    Logger.info("Compiled in #{System.os_time(:millisecond) - start_time}ms")

    Healthchecks.shutting_down(fn -> 
      GenServer.cast(Autopgo.Worker, :readiness_checked) 
    end)

    {:noreply, state}
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

    {:noreply, %{state | port: port}}
  end

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  defp stop_port(port) do
    Logger.info("Stopping port")
    pid = Port.info(port)[:os_pid]
    
    # send interrupt signal to the port
    # this is hack to not require the runned process to handle
    # stdin eof
    System.cmd("kill", ["-INT", "#{pid}"])
  end
end
