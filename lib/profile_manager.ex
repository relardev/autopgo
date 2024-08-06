defmodule ProfileManager do
  def new_profile(url) do
    case Healthchecks.readiness() do
      :ok -> 
        File.ls!("pprof") |> Enum.each(fn x -> File.rm!(Path.join(["pprof", x])) end)
        timestamp = System.os_time(:second)
        [command | args]  = ~w(wget -O pprof/#{timestamp}.pprof #{url})

        {_, 0} = System.cmd(command, args, stderr_to_stdout: true)
        :ok
      {:error, reason} ->  {:error, reason}
    end
  end
end
