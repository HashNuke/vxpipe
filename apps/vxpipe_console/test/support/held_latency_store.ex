defmodule Vxpipe.Console.Test.HeldLatencyStore do
  @moduledoc false
  alias Vxpipe.Persistence.LatencyStore

  def put_run({repo, observer}, %{closed_at: %DateTime{}} = run) do
    send(observer, {:terminal_diagnostic_write, self(), run.id})

    receive do
      :persist_terminal -> LatencyStore.put_run(repo, run)
    after
      2_000 -> {:error, :fixture_write_not_released}
    end
  end

  def put_run({repo, _observer}, run), do: LatencyStore.put_run(repo, run)

  def put_turn({repo, _observer}, tenant, call, incarnation, turn),
    do: LatencyStore.put_turn(repo, tenant, call, incarnation, turn)
end
