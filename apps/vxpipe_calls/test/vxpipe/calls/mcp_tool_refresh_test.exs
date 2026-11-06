defmodule Vxpipe.Calls.MCPToolRefreshTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPConnections, ResolvedMCPConnection}
  alias Vxpipe.Calls.Test.{MCPProbeFixture, MCPRepositoryFixture, MCPRuntimeFixture}
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    saved = %ResolvedMCPConnection{
      connection: %{
        id: "connection",
        tenant_key: @tenant,
        generation: 3,
        status: "connected",
        endpoint: "https://mcp.example.test/mcp",
        auth_method: "oauth",
        catalog: [],
        server_name: "Tools"
      },
      secrets: %{
        "access_token" => "private-access",
        "refresh_token" => "private-refresh",
        "private_key" => "private-key",
        "headers" => [%{"name" => "X-Workspace", "value" => "workspace"}]
      }
    }

    agent = start_supervised!({Agent, fn -> saved end})

    checked = %ResolvedMCPConnection{
      connection: %{server_name: "New tools", catalog: [%{"name" => "lookup"}]},
      secrets: %{"token" => "must-not-save"}
    }

    options = [
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_connection_repository: {MCPRuntimeFixture, {self(), agent}},
      mcp_connection_probe: {MCPProbeFixture, {self(), {:ok, checked}}},
      refresh_authority: fn -> {:ok, principal} end
    ]

    %{principal: principal, options: options, saved: saved, agent: agent}
  end

  test "refresh uses current OAuth bearer and MCP headers, saving only catalog metadata", data do
    assert {:ok, public} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection", 3, data.options)

    assert public.generation == 3
    assert public.auth_method == "oauth"
    assert public.tool_count == 1
    assert_receive {:mcp_probe, @tenant, input}

    assert input == %{
             "endpoint" => data.saved.connection.endpoint,
             "auth_method" => "bearer",
             "credentials" => %{
               "token" => "private-access",
               "headers" => data.saved.secrets["headers"]
             }
           }

    assert_receive {:catalog_refreshed,
                    %{server_name: "New tools", catalog: [%{"name" => "lookup"}]}}

    assert Agent.get(data.agent, & &1.secrets) == data.saved.secrets
    refute inspect(public) =~ "private"
  end

  test "foreign tenants and stale generations cannot trigger a refresh", data do
    assert {:error, :forbidden} =
             MCPConnections.refresh_tools(
               data.principal,
               "BBBBBBBBBBBBBBBB",
               "connection",
               3,
               data.options
             )

    assert {:error, :stale_mcp_connection} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection", 2, data.options)

    refute_received {:mcp_probe, _, _}
    refute_received {:catalog_refreshed, _}
  end

  test "permission loss during validation prevents catalog writes", data do
    revoked = %{data.principal | grants: MapSet.new()}
    options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, revoked} end)

    assert {:error, :forbidden} =
             MCPConnections.refresh_tools(data.principal, @tenant, "connection", 3, options)

    assert_receive {:mcp_probe, _, _}
    refute_received {:catalog_refreshed, _}
    assert Agent.get(data.agent, & &1) == data.saved
  end
end
