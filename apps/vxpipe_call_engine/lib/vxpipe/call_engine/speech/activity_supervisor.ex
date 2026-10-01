defmodule Vxpipe.CallEngine.Speech.ActivitySupervisor do
  @moduledoc false
  use Supervisor

  alias Vxpipe.CallEngine.Speech.ActivityRuntime

  def start_link(options),
    do: Supervisor.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @impl true
  def init(options) do
    tasks = Keyword.fetch!(options, :tasks)
    runtime = Keyword.fetch!(options, :runtime)

    runtime_options =
      options
      |> Keyword.put(:name, runtime)
      |> Keyword.put(:task_supervisor, tasks)

    Supervisor.init(
      [
        # Runtime admission retains each slot through the worker's DOWN signal.
        # A second supervisor quota races with retirement bookkeeping there.
        {Task.Supervisor, name: tasks},
        {ActivityRuntime, runtime_options}
      ],
      strategy: :one_for_all
    )
  end
end
