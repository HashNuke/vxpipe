defmodule Vxpipe.Calls.MCPRuntimeCredentialsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPRuntimeCredentials, ResolvedMCPConnection}
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

  test "valid pinned token is returned without registration or refresh secrets", data do
    assert {:ok, resolved} =
             MCPRuntimeCredentials.resolve("tenant", "connection", 2, data.options)

    assert resolved.secrets == %{"access_token" => "old"}
    refute_received :refreshed
  end

  test "expired token refreshes once then resolves the persisted token", data do
    Agent.update(data.agent, fn saved ->
      %{saved | secrets: Map.put(saved.secrets, "expires_at", DateTime.to_iso8601(@now))}
    end)

    assert {:ok, resolved} =
             MCPRuntimeCredentials.resolve("tenant", "connection", 2, data.options)

    assert resolved.secrets == %{"access_token" => "new"}
    assert_receive :refreshed
    refute_received :refreshed
  end

  test "foreign identity, stale generation and revoked status fail before refresh", data do
    assert {:error, :mcp_connection_unavailable} =
             MCPRuntimeCredentials.resolve("other", "connection", 2, data.options)

    assert {:error, :mcp_connection_unavailable} =
             MCPRuntimeCredentials.resolve("tenant", "connection", 1, data.options)

    Agent.update(data.agent, fn saved ->
      %{saved | connection: %{saved.connection | status: "revoked"}}
    end)

    assert {:error, :mcp_connection_unavailable} =
             MCPRuntimeCredentials.resolve("tenant", "connection", 2, data.options)

    refute_received :refreshed
  end

  test "ambiguous refresh claim never falls back to an otherwise unexpired token", data do
    Agent.update(data.agent, fn saved ->
      %{saved | secrets: Map.put(saved.secrets, "refresh_claim", %{"deadline" => 0})}
    end)

    assert {:error, :oauth_reconnect_required} =
             MCPRuntimeCredentials.resolve("tenant", "connection", 2, data.options)

    refute_received :refreshed
  end
end
