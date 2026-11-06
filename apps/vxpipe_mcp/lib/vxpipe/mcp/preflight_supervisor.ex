defmodule Vxpipe.MCP.PreflightSupervisor do
  @moduledoc false
  use Supervisor
  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  @impl true
  def init(_options) do
    children = [
      {Task.Supervisor, name: Vxpipe.MCP.PreflightTasks},
      {Vxpipe.MCP.PreflightRunner, task_supervisor: Vxpipe.MCP.PreflightTasks}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
