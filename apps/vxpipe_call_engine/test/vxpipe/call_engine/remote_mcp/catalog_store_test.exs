defmodule Vxpipe.CallEngine.RemoteMCP.CatalogStoreTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogStore,
    Integration,
    IntegrationCatalog,
    IntegrationOwner
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.MCP.Catalog

  test "publishes a replacement snapshot without changing an active pinned owner" do
    old_client = protocol_client({:ok, %{"content" => [%{"type" => "text", "text" => "old"}]}})
    new_client = protocol_client({:ok, %{"content" => [%{"type" => "text", "text" => "new"}]}})
    old_catalog = integration_catalog(old_client, "catalog-1", "customer_id")
    new_catalog = integration_catalog(new_client, "catalog-2", "account_id")

    store = start_supervised!({CatalogStore, catalog: old_catalog})
    assert {:ok, old_snapshot} = CatalogStore.snapshot(store)

    assert {:ok, old_remote} =
             IntegrationCatalog.resolve(
               old_snapshot,
               "tenant-demo",
               "records",
               "lookup_customer"
             )

    old_binding = %ToolBinding{
      name: "customer_lookup",
      type: :mcp,
      action: nil,
      remote: old_remote
    }

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-old-catalog",
         integrations: old_snapshot,
         tools: %{"customer_lookup" => old_binding},
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}
    assert :ok = CatalogStore.publish(store, new_catalog)
    assert {:ok, current_snapshot} = CatalogStore.snapshot(store)

    assert {:ok, new_remote} =
             IntegrationCatalog.resolve(
               current_snapshot,
               "tenant-demo",
               "records",
               "lookup_customer"
             )

    assert Map.has_key?(old_remote.input_schema["properties"], "customer_id")
    assert Map.has_key?(new_remote.input_schema["properties"], "account_id")

    assert {:error, :stale_integration} =
             IntegrationCatalog.checkout(current_snapshot, old_remote)

    assert {:ok, %{"content" => [%{"text" => "old", "type" => "text"}]}} =
             IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => "customer-1"})

    assert [%{arguments: %{"customer_id" => "customer-1"}}] = invocations(old_client)
    assert invocations(new_client) == []
  end

  defp integration_catalog(client, catalog_generation, field_name) do
    {:ok, remote_catalog} =
      Catalog.new([
        %{
          "name" => "lookup_customer",
          "description" => "Looks up one customer.",
          "inputSchema" => %{
            "$schema" => "https://json-schema.org/draft/2020-12/schema",
            "type" => "object",
            "properties" => %{field_name => %{"type" => "string"}},
            "required" => [field_name],
            "additionalProperties" => false
          }
        }
      ])

    {:ok, integration} =
      Integration.new(
        integration_id: "records",
        configuration_generation: "configuration-1",
        credential_generation: "credential-1",
        catalog_generation: catalog_generation,
        catalog: remote_catalog,
        allowed_tools: ["lookup_customer"],
        client_config: [test_client: client, test_observer: self()]
      )

    {:ok, catalog} =
      IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-demo" => %{"records" => integration}}
      )

    catalog
  end

  defp protocol_client(response) do
    start_supervised!(
      {Agent, fn -> %{responses: [response], invocations: []} end},
      id: {Agent, make_ref()}
    )
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)
end
