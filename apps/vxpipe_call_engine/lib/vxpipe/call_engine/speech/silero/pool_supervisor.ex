defmodule Vxpipe.CallEngine.Speech.Silero.PoolSupervisor do
  @moduledoc false
  use Supervisor
  require Logger

  alias Vxpipe.CallEngine.Speech.Silero.{Batch, CPUBudget, Pool, Worker}

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @impl true
  def init(opts) do
    budget = CPUBudget.detect(Keyword.get(opts, :budget_options, []))
    pool = Keyword.get(opts, :dispatcher, Pool)

    run = Keyword.get(opts, :run, &Batch.run/2)

    workers =
      for slot <- 1..budget.workers do
        Supervisor.child_spec({Worker, {pool, run}}, id: {Worker, slot})
      end

    worker_tree = %{
      id: Worker.Supervisor,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           workers,
           [strategy: :one_for_one, name: Keyword.get(opts, :workers_name, Worker.Supervisor)]
         ]}
    }

    Logger.info("Silero pool selected #{budget.workers} workers", silero_cpu_budget: budget)
    :telemetry.execute([:vxpipe, :silero, :pool, :start], %{workers: budget.workers}, budget)

    Supervisor.init([{Pool, [name: pool, budget: budget]}, worker_tree], strategy: :rest_for_one)
  end
end
