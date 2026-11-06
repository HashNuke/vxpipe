defmodule Vxpipe.Console.IntegrationsDirectory.Supervisor do
  @moduledoc "Owns the public cache and its fetch workers as one restart boundary."
  use Supervisor

  alias Vxpipe.Console.IntegrationsDirectory.Cache

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    Supervisor.init(
      [
        {Task.Supervisor, name: Vxpipe.Console.IntegrationsDirectory.Tasks, max_children: 8},
        {Cache, name: Cache, task_supervisor: Vxpipe.Console.IntegrationsDirectory.Tasks}
      ],
      strategy: :one_for_all
    )
  end
end
