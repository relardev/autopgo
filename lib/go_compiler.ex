defmodule Autopgo.GoCompiler do
  use GenServer

  require Logger

  def compile_and_distribute() do
    GenServer.call(__MODULE__, {:compile}, :infinity)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    run_dir = Application.get_env(:autopgo, :run_dir)
    run_command = Application.get_env(:autopgo, :run_command)
    default_pprof_path = Application.get_env(:autopgo, :default_pprof_path, "default.pprof")
    compile_command = Application.get_env(:autopgo, :recompile_command)
    [command | _] = String.split(run_command)
    binary_path = Path.join(run_dir, command)

    compile_command = String.replace(compile_command, "{{profile}}", default_pprof_path)

    {:ok,
     %{
       binary_path: binary_path,
       command: compile_command
     }}
  end

  def handle_call({:compile}, _from, state) do
    compile(state)

    data = File.read!(state.binary_path)
    Autopgo.BinaryStore.bump_last_binary_update()
    Autopgo.BinaryStoreDistributed.distribute_binary(data)

    {:reply, :ok, state}
  end

  defp compile(state) do
    go_env = Autopgo.GoEnv.get()
    Logger.info("Compiling with args #{inspect(go_env)}")
    start_time = System.os_time(:millisecond)

    [command | args] = String.split(state.command)
    {_, 0} = System.cmd(command, args, env: go_env)

    Logger.info("Compiled in #{System.os_time(:millisecond) - start_time}ms")

    [command | args] = ~w(go clean -cache)
    {_, 0} = System.cmd(command, args, env: go_env)
  end
end
