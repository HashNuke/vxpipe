defmodule Vxpipe.Calls.EditorToolCatalogTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, Integration, IntegrationCatalog}
  alias Vxpipe.CallEngine.Tool.DelayedReport
  alias Vxpipe.Calls.EditorToolCatalog

  test "projects registered tools and the tenant MCP snapshot without live discovery or secrets" do
    {:ok, descriptors} =
      Vxpipe.MCP.Catalog.new([
        %{
          "name" => "find_slots",
          "description" => "Find available times",
          "inputSchema" => %{"type" => "object"}
        }
      ])

    {:ok, integration} =
      Integration.new(
        integration_id: "calendar",
        catalog: descriptors,
        allowed_tools: ["find_slots"],
        configuration_generation: "1",
        credential_generation: "1",
        catalog_generation: "1",
        client_config: [private: "never-expose-this"]
      )

    {:ok, catalog} = IntegrationCatalog.new(tenants: %{"tenant" => %{"calendar" => integration}})
    store = start_supervised!({CatalogStore, catalog: catalog})

    options = [
      mcp_catalog_store: store,
      registries: %{
        host_tools: %{"prepare_background_report" => DelayedReport, "wrong_name" => DelayedReport}
      }
    ]

    result = EditorToolCatalog.list("tenant", options)
    assert result.mcp_available

    assert Enum.map(result.tools, &{&1.type, &1.tool}) == [
             {"host", "prepare_background_report"},
             {"platform", "get_current_time"},
             {"platform", "hangup"},
             {"mcp", "find_slots"}
           ]

    assert List.last(result.tools) == %{
             type: "mcp",
             integration: "calendar",
             tool: "find_slots",
             description: "Find available times"
           }

    refute inspect(result) =~ "never-expose-this"
    refute Enum.any?(EditorToolCatalog.list("other", options).tools, &(&1.type == "mcp"))
  end

  test "default picker uses saved tenant connections with stable IDs and cached tools" do
    row = %{
      id: "connection-id",
      tenant_key: "tenant",
      generation: 3,
      status: "connected",
      server_name: "Calendar",
      catalog: [
        %{
          "name" => "find_slots",
          "description" => "Find times",
          "inputSchema" => %{"type" => "object"}
        }
      ]
    }

    options = [mcp_connection_repository: {Vxpipe.Calls.Test.MCPCatalogFixture, {:ok, [row]}}]
    result = EditorToolCatalog.list("tenant", options)
    assert result.mcp_available

    assert Enum.find(result.tools, &(&1.type == "mcp")) == %{
             type: "mcp",
             integration: "connection-id",
             tool: "find_slots",
             description: "Find times"
           }

    foreign =
      Keyword.put(
        options,
        :mcp_connection_repository,
        {Vxpipe.Calls.Test.MCPCatalogFixture, {:ok, [%{row | tenant_key: "other"}]}}
      )

    refute EditorToolCatalog.list("tenant", foreign).mcp_available
    refute Enum.any?(EditorToolCatalog.list("tenant", foreign).tools, &(&1.type == "mcp"))
  end

  test "saved connection outage keeps native tools but does not fall back to application MCPs" do
    {:ok, original} = CatalogStore.snapshot()

    {:ok, catalog} =
      Vxpipe.MCP.Catalog.new([
        %{"name" => "fallback_tool", "inputSchema" => %{"type" => "object"}}
      ])

    {:ok, integration} =
      Integration.new(
        integration_id: "fallback",
        catalog: catalog,
        allowed_tools: ["fallback_tool"],
        configuration_generation: "1",
        credential_generation: "1",
        catalog_generation: "1",
        client_config: []
      )

    {:ok, configured} = IntegrationCatalog.new(application: %{"fallback" => integration})
    :ok = CatalogStore.publish(CatalogStore, configured)
    on_exit(fn -> CatalogStore.publish(CatalogStore, original) end)
    assert [%{tool: "fallback_tool"}] = IntegrationCatalog.tools(configured, "tenant")

    result =
      EditorToolCatalog.list("tenant",
        mcp_connection_repository: {Vxpipe.Calls.Test.MCPCatalogFixture, {:error, :unavailable}}
      )

    refute result.mcp_available
    refute Enum.any?(result.tools, &(&1.type == "mcp"))
    assert Enum.any?(result.tools, &(&1.type == "platform"))
  end

  test "saved picker omits unsupported input schemas while preserving executable siblings" do
    row = %{
      id: "connection",
      tenant_key: "tenant",
      generation: 1,
      status: "connected",
      catalog: [
        %{"name" => "valid", "inputSchema" => %{"type" => "object"}},
        %{
          "name" => "unsupported",
          "inputSchema" => %{"$ref" => "https://schemas.example.test/tool.json"}
        }
      ]
    }

    options = [mcp_connection_repository: {Vxpipe.Calls.Test.MCPCatalogFixture, {:ok, [row]}}]
    result = EditorToolCatalog.list("tenant", options)
    assert result.mcp_available

    assert Enum.filter(result.tools, &(&1.type == "mcp")) == [
             %{type: "mcp", integration: "connection", tool: "valid", description: ""}
           ]

    assert Enum.any?(result.tools, &(&1.type == "platform"))
    assert {:ok, catalog} = Vxpipe.Calls.SavedMCPCompilationCatalog.build("tenant", options)

    assert {:error, :unsupported_input_schema} =
             IntegrationCatalog.resolve(catalog, "tenant", "connection", "unsupported")
  end

  test "keeps built-in tools available when the MCP catalog store is unavailable" do
    result =
      EditorToolCatalog.list("tenant",
        mcp_catalog_store: :missing_editor_catalog,
        registries: %{host_tools: %{}}
      )

    refute result.mcp_available
    assert Enum.map(result.tools, & &1.tool) == ["get_current_time", "hangup"]
  end
end
