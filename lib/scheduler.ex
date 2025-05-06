defmodule Autopgo.Scheduler do
  use Quantum, otp_app: :autopgo

  def next(job) when is_atom(job) do
    node = node(Highlander.pid(__MODULE__))
    %{schedule: s} = :erpc.call(node, Autopgo.Scheduler, :find_job, [job])

    Crontab.Scheduler.get_next_run_date!(s)
    |> DateTime.from_naive!("Etc/UTC")
  end
end
