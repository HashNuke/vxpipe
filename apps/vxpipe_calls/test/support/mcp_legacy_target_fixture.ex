defmodule Vxpipe.Calls.Test.MCPLegacyTargetFixture do
  def check(owner, _tenant, _input) do
    send(owner, :legacy_protocol_called)
    {:error, :mcp_authentication_required}
  end

  def prepare(owner, _tenant, _input, _origin) do
    send(owner, :legacy_protocol_called)
    {:error, :oauth_registration_unavailable}
  end
end
