defmodule Vxpipe.Calls.Test.MCPProbeFixture do
  def discover({owner, result}, tenant, input) do
    send(owner, {:mcp_preflight, tenant, input})
    result
  end

  def check({owner, result}, tenant, input) do
    send(owner, {:mcp_probe, tenant, input})
    result
  end
end
