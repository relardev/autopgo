defmodule Autopgo do
  require Logger

  def restart(notify_fn \\ fn _ -> :ok end) do
    :ok = GenServer.cast(Autopgo.Worker, {:restart, notify_fn})
  end

  def run_base_binary() do
    :ok = GenServer.cast(Autopgo.Worker, :run_base_binary)
  end
end
