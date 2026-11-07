defmodule Vxpipe.Calls.MCPMachineConnectionsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPConnections, ResolvedMCPConnection}
  alias Vxpipe.Calls.Test.{MCPProbeFixture, MCPRepositoryFixture}
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

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "revision" => "draft",
      "auth_method" => "own_client",
      "credentials" => %{
        "grant_type" => "client_credentials",
        "client_id" => "registered",
        "client_auth_method" => "client_secret_post",
        "client_secret" => "secret"
      }
    }

    checked = %ResolvedMCPConnection{
      connection: %{
        endpoint: input["endpoint"],
        endpoint_identity: input["endpoint"],
        auth_method: "oauth",
        server_name: "Machine MCP",
        catalog: [],
        directory_id: nil
      },
      secrets: %{"grant_type" => "client_credentials", "access_token" => "private-access"}
    }

    options = [
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_connection_repository: {MCPRepositoryFixture, self()},
      mcp_connection_probe: {MCPProbeFixture, {self(), {:ok, checked}}},
      refresh_authority: fn -> {:ok, principal} end
    ]

    %{principal: principal, input: input, options: options}
  end

  test "machine connection reuses authorized create and generation-checked replacement", data do
    assert {:ok, public} =
             MCPConnections.connect(data.principal, @tenant, data.input, data.options)

    assert public.auth_method == "oauth"
    refute Map.has_key?(public, :secrets)
    assert_receive {:mcp_probe, @tenant, input}
    assert input == data.input

    assert_receive {:mcp_create, @tenant, %{auth_method: "oauth"},
                    %{"access_token" => "private-access"}}

    assert {:ok, replaced} =
             MCPConnections.update(
               data.principal,
               @tenant,
               "connection-id",
               3,
               data.input,
               data.options
             )

    assert replaced.generation == 4
    assert_receive {:mcp_replace, @tenant, "connection-id", 3, _}
  end

  test "delegated grants cannot bypass consent through direct create", data do
    input = put_in(data.input, ["credentials", "grant_type"], "authorization_code")

    assert {:error, :invalid_mcp_configuration} =
             MCPConnections.connect(data.principal, @tenant, input, data.options)

    refute_received {:mcp_probe, _, _}
    refute_received {:mcp_create, _, _, _}
  end

  test "permissions revoked during machine token acquisition prevent persistence", data do
    authority = start_supervised!({Agent, fn -> data.principal end})
    revoked = %{data.principal | grants: MapSet.new()}

    options =
      data.options
      |> Keyword.put(:refresh_authority, fn -> {:ok, Agent.get(authority, & &1)} end)
      |> Keyword.update!(:mcp_connection_probe, fn {module, {owner, result}} ->
        {module, {owner, result, {:on_check, fn -> Agent.update(authority, fn _ -> revoked end) end}}}
      end)

    assert {:error, :forbidden} =
             MCPConnections.connect(data.principal, @tenant, data.input, options)

    assert_receive {:mcp_probe, _, _}
    refute_received {:mcp_create, _, _, _}
  end
end
