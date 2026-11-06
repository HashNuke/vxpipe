defmodule Vxpipe.Console.MCPConnectionProbeTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPConnectionProbe

  test "static adapter projects the canonical endpoint and keeps credentials in the opaque snapshot" do
    owner = self()

    check = fn tenant, configuration ->
      send(owner, {:checked, tenant, configuration.auth_method})
      {:ok, %{server_name: "Calendar", catalog: []}}
    end

    input = %{
      "endpoint" => "https://MCP.example.test:443/mcp?region=eu",
      "auth_method" => "bearer",
      "credentials" => %{"token" => "synthetic-private-token"}
    }

    assert {:ok, result} = MCPConnectionProbe.check([connection_check: check], "tenant", input)
    assert result.connection.endpoint == "https://mcp.example.test/mcp?region=eu"
    assert result.connection.endpoint_identity == result.connection.endpoint
    assert result.connection.directory_id == nil
    assert result.secrets == input["credentials"]
    refute inspect(result) =~ "synthetic-private-token"
    refute inspect(result.connection) =~ "synthetic-private-token"
    assert_receive {:checked, "tenant", "bearer"}
  end

  test "credential query parameters never reach the connection check or public projection" do
    owner = self()

    check = fn _, _ ->
      send(owner, :unexpected_check)
      {:ok, %{server_name: "Calendar", catalog: []}}
    end

    for method <- ~w(none bearer headers basic) do
      assert {:error, :invalid_mcp_endpoint} =
               MCPConnectionProbe.check(
                 [connection_check: check],
                 "tenant",
                 %{
                   "endpoint" => "https://mcp.example.test/mcp?%61ccess_token=private-marker",
                   "auth_method" => method,
                   "credentials" => %{}
                 }
               )
    end

    refute_received :unexpected_check
  end
end
