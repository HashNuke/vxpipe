defmodule Vxpipe.CallEngine.RemoteMCP.Activation do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.{IntegrationCatalog, IntegrationOwner}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  def selected?(tools) do
    Enum.any?(tools, fn
      {_name, %ToolBinding{type: :mcp}} -> true
      _entry -> false
    end)
  end

  def children(options) do
    with {:ok, source} <- IntegrationCatalog.restart_source(Keyword.get(options, :integrations)) do
      sessions = Keyword.fetch!(options, :session_supervisor)
      options = Keyword.put(options, :integrations, source)

      [
        Supervisor.child_spec({DynamicSupervisor, strategy: :one_for_one, name: sessions},
          id: :remote_mcp_sessions
        ),
        Supervisor.child_spec({IntegrationOwner, options}, id: :remote_mcp_owner)
      ]
    else
      _invalid -> raise ArgumentError, "remote MCP integrations are unavailable"
    end
  end
end
