defmodule Vxpipe.CallEngine.Speech.Silero.PoolSupervisorTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.{Pool, PoolSupervisor, Worker}

  test "the node starts an automatically sized worker pool" do
    children = Supervisor.which_children(Worker.Supervisor)
    budget = Vxpipe.CallEngine.Speech.Silero.CPUBudget.detect()
    assert worker_count(children) == budget.workers
  end

  test "a new pool samples its current CPU budget on each startup" do
    for workers <- [1, 2, 4] do
      start_supervised!(
        {PoolSupervisor,
         name: __MODULE__,
         dispatcher: __MODULE__.Pool,
         workers_name: __MODULE__.Workers,
         budget_options: [linux?: false, logical_processors: 4, dirty_schedulers: workers]}
      )

      assert worker_count(Supervisor.which_children(__MODULE__.Workers)) == workers
      assert %{active_workers: ^workers} = Pool.status(__MODULE__.Pool)
      stop_supervised!(PoolSupervisor)
    end
  end

  defp worker_count(children) do
    Enum.count(children, fn
      {{Worker, _slot}, pid, :worker, [Worker]} when is_pid(pid) -> true
      _ -> false
    end)
  end
end
