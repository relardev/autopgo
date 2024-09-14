defmodule Autopgo.GoEnv do
  def get() do
    target =
      Autopgo.MemoryMonitor.free()
      |> (fn x -> x / 2 end).()
      |> trunc()

    [{"GOMAXPROCS", "1"}, {"GOMEMLIMIT", "#{target}MiB"}]
  end
end
