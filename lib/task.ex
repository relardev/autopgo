defmodule Autopgo.Task do
  require Logger

  def go!() do
    Logger.info("Starting the autopgo process, gathering profiles")
    ask_for_profile!()
    Logger.info("Profile gathered, compiling")
    compile!()
    Logger.info("Compilation done, restarting all")
    Autopgo.Worker.restart_all()
    Logger.info("Done restarting")
  end

  defp ask_for_profile! do
    pid = self()

    Autopgo.ProfileManager.gather_profiles(fn ->
      send(pid, :profile_gathered)
    end)

    receive do
      :profile_gathered ->
        nil
    after
      10 * 60 * 1000 ->
        raise("Profile gathering timed out")
    end
  end

  defp compile!() do
    node = Autopgo.MemoryMonitor.select_node_with_lowest_memory_usage()
    Logger.info("Compiling on #{node}")

    Autopgo.ProfileManager.send_profile(node)

    %Task{ref: ref} =
      Task.Supervisor.async_nolink(
        {Autopgo.Compilation.TaskSupervisor, node},
        Autopgo.GoCompiler,
        :compile_and_distribute,
        []
      )

    receive do
      {:DOWN, ^ref, :process, _pid, :shutdown} ->
        Logger.info("Compilation failed, with :shutdown, retrying")
        compile!()

      {:DOWN, ^ref, :process, _pid, reason} ->
        Logger.info("Compilation failed: #{inspect(reason)}, stopping attempt")
        raise("Compilation failed")

      {^ref, :ok} ->
        Logger.info("Compilation succeeded")
    after
      10 * 60 * 1000 ->
        raise("Compilation timed out")
    end
  end
end
