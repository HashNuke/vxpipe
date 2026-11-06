defmodule Vxpipe.Calls.MCPTransportCredentialsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ResolvedMCPConnection
  alias Vxpipe.Calls.Test.MCPRuntimeFixture
  @now ~U[2026-11-06 12:00:00Z]

  setup do
    saved = %ResolvedMCPConnection{
      connection: %{
        id: "connection",
        tenant_key: "tenant",
        generation: 2,
        auth_method: "oauth",
        status: "connected"
      },
      secrets: %{
        "access_token" => "old",
        "refresh_token" => "private-refresh",
        "expires_at" => "2026-11-06T12:05:00Z"
      }
    }

    agent = start_supervised!({Agent, fn -> saved end})
    port = {MCPRuntimeFixture, {self(), agent}}

    %{
      agent: agent,
      options: [
        mcp_connection_repository: port,
        mcp_oauth_grant_repository: port,
        mcp_oauth_refresh: port,
        now: fn -> @now end
      ]
    }
  end

  test "transport projection exposes only a current token or static method", data do
    assert {:ok, %{auth_method: "oauth", token: "old"}} =
             Vxpipe.Calls.MCPTransportCredentials.resolve(data.options, "tenant", "connection", 2)

    Agent.update(data.agent, fn saved ->
      %{
        saved
        | connection: %{saved.connection | auth_method: "bearer"},
          secrets: %{"token" => "static-private"}
      }
    end)

    assert {:ok, %{auth_method: "bearer"}} =
             Vxpipe.Calls.MCPTransportCredentials.resolve(data.options, "tenant", "connection", 2)

    assert {:error, :mcp_connection_unavailable} =
             Vxpipe.Calls.MCPTransportCredentials.resolve(data.options, "tenant", "connection", 1)
  end
end
