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
    limit = Keyword.get(options, :max_jobs, 1)

    runtime_options =
      options
      |> Keyword.put(:name, runtime)
      |> Keyword.put(:task_supervisor, tasks)

    Supervisor.init(
      [
        {Task.Supervisor, name: tasks, max_children: limit},
        {ActivityRuntime, runtime_options}
      ],
      strategy: :one_for_all
    )
  end
end
