defmodule Vxpipe.Console.MCPPreflight do
  @moduledoc "Composes the bounded credentialless MCP discovery port."
  @behaviour Vxpipe.Calls.MCPPreflight
  @impl true
  def discover(options, tenant, input) do
    runner = Keyword.get(options, :preflight_runner, Vxpipe.MCP.PreflightRunner)

    Vxpipe.MCP.PreflightRunner.run(runner, tenant, fn ->
      Vxpipe.MCP.Preflight.discover(tenant, input, options)
    end)
  catch
    :exit, _reason -> {:error, :mcp_discovery_unavailable}
  end
end
