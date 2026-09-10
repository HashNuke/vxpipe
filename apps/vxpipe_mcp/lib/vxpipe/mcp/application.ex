defmodule Vxpipe.MCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Vxpipe.MCP.ConnectionRegistry},
      Vxpipe.MCP.CredentialLeases,
      {DynamicSupervisor, strategy: :one_for_one, name: Vxpipe.MCP.ConnectionSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Vxpipe.MCP.Supervisor)
  end
end
