defmodule Autopgo do
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
    port = Port.open({:spawn, args.binary_path}, [:binary, :exit_status])
    {:ok, Map.merge(args, %{port: port})}
  end

  def handle_cast(:recompile, state) do
    [command | args] = String.split(state.recompile_command)
    {_, 0} = System.cmd(command, args)

    stop_port(state.port)

    {:noreply, state}
  end

  def handle_info({port, :closed}, state) do
    Logger.info("Port closed")
    {:noreply, %{state | port: port}}
  end

  def handle_info({port, {:data, data}}, state) do
    dbg(data)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, state) do
    Logger.info("Port exited with status #{status}, restarting...")
    port = Port.open({:spawn, state.binary_path}, [:binary, :exit_status])
    {:noreply, %{state | port: port}}
  end

  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  defp stop_port(port) do
    pid = Port.info(port)[:os_pid]
    
    # send interrupt signal to the port
    # this is hack to not require the runned process to handle
    # stdin eof
    System.cmd("kill", ["-INT", "#{pid}"])
  end
end
