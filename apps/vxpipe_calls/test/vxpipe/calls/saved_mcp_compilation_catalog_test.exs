defmodule Vxpipe.Calls.SavedMCPCompilationCatalogTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog
  alias Vxpipe.Calls.SavedMCPCompilationCatalog

  test "compiles cached tenant tools without resolving credentials or application fallback" do
    assert {:ok, catalog} = build([record()])
    assert {:ok, tool} = IntegrationCatalog.resolve(catalog, "tenant", "connection", "lookup")
    assert tool.scope == {:tenant, "tenant"}
    assert tool.configuration_generation == "3"
    assert tool.credential_generation == "3"
    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, tool)
    assert integration.client_config == []

    assert {:error, :integration_not_configured} =
             IntegrationCatalog.resolve(catalog, "other", "connection", "lookup")
  end

  test "empty and zero-tool connections produce a usable empty catalog" do
    for records <- [[], [%{record() | catalog: []}]] do
      assert {:ok, catalog} = build(records)
      assert IntegrationCatalog.tools(catalog, "tenant") == []
    end
  end

  test "rejects foreign, revoked, duplicate and malformed saved records" do
    for records <- [
          [%{record() | tenant_key: "other"}],
          [%{record() | status: "revoked"}],
          [record(), record()],
          [%{record() | catalog: [%{"name" => "lookup", "inputSchema" => nil}]}]
        ] do
      assert {:error, :mcp_catalog_unavailable} = build(records)
    end
  end

  test "configuration and schema changes invalidate previously resolved tools" do
    assert {:ok, initial} = build([record()])
    assert {:ok, tool} = IntegrationCatalog.resolve(initial, "tenant", "connection", "lookup")

    changed_schema = [
      %{
        "name" => "lookup",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["id"],
          "properties" => %{"id" => %{"type" => "string"}}
        }
      }
    ]

    for record <- [%{record() | generation: 4}, %{record() | catalog: changed_schema}] do
      assert {:ok, changed} = build([record])
      assert {:error, :stale_integration} = IntegrationCatalog.checkout(changed, tool)
    end
  end

  defp build(records) do
    SavedMCPCompilationCatalog.build("tenant",
      mcp_connection_repository: {Vxpipe.Calls.Test.MCPCatalogFixture, {:ok, records}}
    )
  end

  defp record do
    %{
      id: "connection",
      tenant_key: "tenant",
      generation: 3,
      status: "connected",
      catalog: [%{"name" => "lookup", "inputSchema" => %{"type" => "object"}}]
    }
  end
end
