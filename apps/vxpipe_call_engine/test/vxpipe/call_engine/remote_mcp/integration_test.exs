defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.Integration
  alias Vxpipe.MCP.Catalog

  test "rejects malformed private client configuration before runtime startup" do
    {:ok, catalog} =
      Catalog.new([
        %{"name" => "lookup", "inputSchema" => %{"type" => "object"}}
      ])

    assert {:error, :invalid_integration} =
             Integration.new(
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               catalog: catalog,
               allowed_tools: ["lookup"],
               client_config: ["not-a-keyword-list"]
             )
  end
end
