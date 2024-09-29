defmodule Autopgo do
  require Logger

  def restart(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(Autopgo.Worker, {:restart, notify_fn})
  end

  def run_base_binary() do
    :ok = GenServer.cast(Autopgo.Worker, :run_base_binary)
  end

  def write_binary(data) do
    :ok = GenServer.call(Autopgo.Worker, {:write_binary, data})
  end

  def read_binary(node, into) do
    Logger.info("Pulling binary from #{node}")
    destination_stream = File.stream!(into)

    GenServer.call(
      {Autopgo.Worker, node},
      {:read_binary, destination_stream}
    )
    |> case do
      :ok ->
        Logger.info("Binary pulled successfully")
        File.chmod!(into, 0o755)
        :ok

      :error ->
        File.rm(into)
        {:error, "Failed to pull binary"}
    end
  end
end
