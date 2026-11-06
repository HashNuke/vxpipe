defmodule Vxpipe.MCP.OAuthCompletionSupervisor do
  @moduledoc false
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    children = [
      {Task.Supervisor, name: Vxpipe.MCP.OAuthCompletionTasks},
      {Vxpipe.MCP.PreflightRunner,
       name: Vxpipe.MCP.OAuthCompletionRunner,
       task_supervisor: Vxpipe.MCP.OAuthCompletionTasks,
       interval: 0}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
