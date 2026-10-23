defmodule Vxpipe.Calls.EditorToolCatalogTest do
  use ExUnit.Case, async: true

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
