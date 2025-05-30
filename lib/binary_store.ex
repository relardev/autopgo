defmodule Autopgo.BinaryStore do
  use GenServer

  require Logger

  def bump_last_binary_update() do
    GenServer.cast(__MODULE__, :bump_last_binary_update)
  end

  def read_binary(node, into) do
    Logger.info("Pulling binary from #{node}")
    destination_stream = File.stream!(into)

    result =
      try do
        GenServer.call(
          {__MODULE__, node},
          {:read_binary, destination_stream},
          60_000
        )
      catch
        type, value -> {:error, "Failed to pull binary exc - #{inspect(type)}, #{inspect(value)}"}
      end

    case result do
      :ok ->
        Logger.info("Binary pulled successfully")
        File.chmod!(into, 0o755)
        :ok

      {:error, reason} ->
        File.rm(into)
        {:error, "Failed to pull binary, #{reason}"}
    end
  end

  def binary_path() do
    GenServer.call(__MODULE__, :binary_path)
  end

  def get_last_binary_updates() do
    {result, bad_nodes} = GenServer.multi_call(Node.list(), __MODULE__, :get_last_binary_update)

    if length(bad_nodes) > 0 do
      Logger.info("get_last_binary_updates BAD NODES: #{bad_nodes}")
    end

    result
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    [command | _] = String.split(args.run_command)
    binary_path = Path.join(args.run_dir, command)
    File.exists?(binary_path) || raise("your program not found under: #{binary_path}")

    Process.send_after(self(), :update_binary, 5 * 60 * 1000)

    {:ok,
     %{
       last_binary_update: nil,
       retry_check_for_binary_minutes: 15,
       binary_path: binary_path
     }}
  end

  def handle_cast(:bump_last_binary_update, state) do
    {:noreply, %{state | last_binary_update: DateTime.utc_now()}}
  end

  def handle_call(:get_last_binary_update, _from, %{last_binary_update: lbu} = state) do
    {:reply, lbu, state}
  end

  def handle_call(:binary_path, _from, state) do
    there_is_a_new_binary = File.exists?("#{state.binary_path}_new")

    if there_is_a_new_binary do
      Logger.info("New binary found, moving it to #{state.binary_path}")
      File.rename!("#{state.binary_path}_new", state.binary_path)
    end

    {:reply, state.binary_path, state}
  end

  def handle_call({:write_binary, data}, _from, state) do
    Logger.info("Writing new binary to #{state.binary_path}_new")
    File.write!("#{state.binary_path}_new", data)
    File.chmod!("#{state.binary_path}_new", 0o755)
    {:reply, :ok, %{state | last_binary_update: DateTime.utc_now()}}
  end

  def handle_call({:read_binary, destination_stream}, _from, state) do
    Logger.info("Reading binary from #{state.binary_path}")

    try do
      source_stream = File.stream!(state.binary_path, 2048)
      Enum.into(source_stream, destination_stream)
      {:reply, :ok, state}
    catch
      type, value ->
        Logger.error("Failed to read binary exc - #{inspect(type)}, #{inspect(value)}")
        {:reply, {:error, {type, value}}, state}
    end
  end

  def handle_info(:update_binary, state) do
    diff =
      Autopgo.Scheduler.next(:autopgo)
      |> DateTime.diff(DateTime.utc_now(), :minute)

    if diff > state.retry_check_for_binary_minutes do
      Logger.info("Profile in more than 15 min, checking for new binary")

      if Autopgo.BinaryStoreDistributed.get_newest_binary(state.binary_path) == :ok do
        Autopgo.Worker.restart()
      end
    else
      Logger.info("Profile in less than 15 min, not checking for new binary")
    end

    {:noreply, state}
  end
end

defmodule Autopgo.BinaryStoreDistributed do
  require Logger

  def distribute_binary(data) do
    Logger.info("Distributing binary to OTHER nodes")

    {_results, bad_nodes} =
      GenServer.multi_call(Node.list(), Autopgo.BinaryStore, {:write_binary, data}, 5 * 60 * 1000)

    Enum.each(bad_nodes, fn node -> Logger.info("Failed to distribute binary to #{node}") end)
  end

  def get_newest_binary(binary_path) do
    file_path = "#{binary_path}_new"

    with {:ok, node} <-
           find_newest_binary() |> Context.add("No new binary found"),
         :ok <- Autopgo.BinaryStore.read_binary(node, file_path) do
      :ok
    else
      {:error, reason} ->
        Logger.info(reason)
        :error
    end
  end

  def find_newest_binary do
    nodes = Node.list()

    if length(nodes) > 0 do
      Autopgo.BinaryStore.get_last_binary_updates()
      |> Enum.filter(fn {_, datetime} -> datetime != nil end)
      |> Enum.max_by(&elem(&1, 1), DateTime, fn -> :error end)
      |> case do
        {node, _datetime} ->
          {:ok, node}

        :error ->
          {:error, "No nodes have binary updated"}
      end
    else
      {:error, "Not in a cluster"}
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
