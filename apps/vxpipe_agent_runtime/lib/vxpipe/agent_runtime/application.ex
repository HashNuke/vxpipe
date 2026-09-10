defmodule Vxpipe.AgentRuntime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Vxpipe.AgentRuntime.RequestSupervisor}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.AgentRuntime.Supervisor
    )
  end
end
