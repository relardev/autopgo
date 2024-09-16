defmodule Autopgo.ProfileManager do
  use GenServer

  require Logger

  def gather_profiles(callback) do
    GenServer.call(__MODULE__, {:gather_profiles, callback})
  end

  def send_profile(node) do
    if node == Node.self() do
      Logger.info("Skipping sending profile to self")
    else
      GenServer.call(__MODULE__, {:send_profile, node})
    end
  end

  def receive_stream(input_stream) do
    GenServer.call(__MODULE__, {:receive_stream, input_stream})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    File.mkdir_p!(args.profile_dir)

    profiling_time_seconds =
      Application.get_env(:autopgo, :profile_url)
      |> URI.parse()
      |> Map.get(:query)
      |> URI.decode_query()
      |> Map.get("seconds")
      |> String.to_integer()

    {:ok,
     %{
       url: args.url,
       profile_dir: args.profile_dir,
       default_pprof_path: args.default_pprof_path,
       profiling_timeout_seconds: profiling_time_seconds + 10,
       machine_state: :waiting,
       callback: nil,
       timer_cancel: nil,
       responses_remaining: 0
     }}
  end

  def handle_call({:send_profile, node}, _from, state) do
    Logger.info("Sending profile to #{node}")
    source_stream = File.stream!(state.default_pprof_path, 2048)

    :ok =
      :erpc.call(node, Autopgo.ProfileManager, :receive_stream, [
        source_stream
      ])

    {:reply, :ok, state}
  end

  def handle_call(
        {:receive_stream, input_stream},
        _from,
        state
      ) do
    Logger.info("Receiving profile on #{Node.self()}")
    write_stream = File.stream!(state.default_pprof_path)
    Enum.into(input_stream, write_stream)
    {:reply, :ok, state}
  end

  def handle_call({:gather_profiles, _callback}, _from, %{machine_state: :gathering} = state),
    do: {:reply, {:error, "busy"}, state}

  def handle_call({:gather_profiles, callback}, _from, state) do
    File.ls!(state.profile_dir)
    |> Enum.each(fn x -> File.rm(Path.join([state.profile_dir, x])) end)

    nodes = [Node.self() | Node.list()]

    nodes
    |> Enum.each(fn node ->
      GenServer.cast({__MODULE__, node}, {:new_profile, self()})
    end)

    timer_cancel = Process.send_after(self(), :done, state.profiling_timeout_seconds * 1000)

    {:reply, :ok,
     %{
       state
       | machine_state: :gathering,
         timer_cancel: timer_cancel,
         callback: callback,
         responses_remaining: length(nodes)
     }}
  end

  def handle_cast({:new_profile, to}, state) do
    Logger.info("Profiling the app")
    new_profile(state.url, to, 0)
    Logger.info("Profiling the app done")
    {:noreply, state}
  end

  defp new_profile(_, to, 10), do: send(to, {:new_profile_error, "Failed to download pprof file"})

  defp new_profile(url, to, count) do
    case Healthchecks.readiness() do
      :ok ->
        result = Req.get!(url, receive_timeout: 2 * 60 * 1000)

        send(to, {:gathered_profile, result, Node.self()})

      {:error, _} ->
        :timer.sleep(2000)
        new_profile(url, to, count + 1)
    end
  end

  def handle_info(:done, %{machine_state: :waiting} = state) do
    Logger.error("Got 'done' but was not expecting it")
    {:noreply, state}
  end

  def handle_info(:done, state) do
    Process.cancel_timer(state.timer_cancel)

    combine_profiles(state.profile_dir, state.default_pprof_path)

    state.callback.()
    {:noreply, %{state | machine_state: :waiting}}
  end

  def handle_info({:gathered_profile, result, from}, state) do
    Logger.info("Gathered profile from #{from}")
    save_profile(result, from, state.profile_dir)
    responses_remaining = state.responses_remaining - 1

    if responses_remaining == 0 do
      send(self(), :done)
    end

    {:noreply, %{state | responses_remaining: responses_remaining}}
  end

  defp save_profile(result, from, profile_dir) do
    timestamp = System.os_time(:second)
    :ok = File.write!("#{profile_dir}/#{timestamp}_#{from}.pprof", result.body)
  end

  defp combine_profiles(profile_dir, output_path) do
    files = File.ls!("#{profile_dir}/")

    profiles_files =
      files
      |> Enum.map(&Path.join(["#{profile_dir}", &1]))
      |> Enum.join(" ")

    Logger.info("Combining #{Enum.count(files)} profiles")
    [command | args] = ~w(go tool pprof -proto #{profiles_files})

    {merged_profile_data, 0} = System.cmd(command, args, env: Autopgo.GoEnv.get())

    {:ok, fd} = File.open(output_path, [:write, :binary, :raw, :sync])

    :ok = IO.binwrite(fd, merged_profile_data)

    :ok = :file.datasync(fd)

    :ok = File.close(fd)
  end
end
