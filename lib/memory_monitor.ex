defmodule Autopgo.MemoryMonitor do
  use GenServer

  def free do
    GenServer.call(__MODULE__, :free)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    case Map.get(args, :fake, false) do
      true ->
        {:ok,
         %{
           fake: true
         }}

      false ->
        {:ok,
         %{
           available_memory: mem_from_file(args.available_memory_file),
           used_memory_file: args.used_memory_file,
           fake: false
         }}
    end
  end

  def handle_call(:free, _from, %{fake: true} = state) do
    {:reply, :rand.uniform(500) + 200, state}
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

  def byte_to_mb(bytes) do
    bytes / 1024 / 1024
  end
end
