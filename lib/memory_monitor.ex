defmodule Autopgo.MemoryMonitor do
  use GenServer

  require Logger

  def free do
    GenServer.call(__MODULE__, :free)
  end

  def select_node_with_lowest_memory_usage() do
    {replies, bad_nodes} =
      GenServer.multi_call(
        __MODULE__,
        :free
      )

    {node, free_mem} = Enum.max_by(replies, fn {_, free} -> free end)

    Logger.info("Selected node #{node} with #{free_mem}MB free memory")

    if length(bad_nodes) > 0 do
      Logger.info("BAD NODES: #{bad_nodes}")
    end

    node
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(%{fake: true}) do
    {:ok,
     %{
       fake: true,
       response: 700
     }}
  end

  def init(%{fake: false} = args) do
    available_memory_file = find_first_existing(args.available_memory_files)
    used_memory_file = find_first_existing(args.used_memory_files)

    {:ok,
     %{
       available_memory: mem_from_file(available_memory_file),
       used_memory_file: used_memory_file,
       fake: false
     }}
  end

  defp find_first_existing(files) do
    Enum.reduce_while(
      files,
      nil,
      fn file, acc ->
        if File.exists?(file) do
          {:halt, file}
        else
          {:cont, acc}
        end
      end
    )
  end

  def handle_call(:free, _from, %{fake: true} = state) do
    result = state.response + :rand.uniform(200)
    {:reply, result, state}
  end

  def handle_call(
        :free,
        _from,
        %{available_memory: available_memory, used_memory_file: used_memory_file} = state
      ) do
    used = mem_from_file(used_memory_file)
    {:reply, available_memory - used, state}
  end

  def mem_from_file(file) do
    file
    |> File.read!()
    |> String.trim()
    |> String.to_integer()
    |> byte_to_mb()
  end

  def byte_to_mb(bytes), do: bytes / 1024 / 1024
end
