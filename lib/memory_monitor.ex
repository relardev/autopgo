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
           fake: true,
           response: 700
         }}

      false ->
        available_memory_file = find_first_existing(args.available_memory_files)
        used_memory_file = find_first_existing(args.used_memory_files)

        {:ok,
         %{
           available_memory: mem_from_file(available_memory_file),
           used_memory_file: used_memory_file,
           fake: false
         }}
    end
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
    {:reply, state.response, state}
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
