defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefreshTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogRefresh, CatalogStore, ConfiguredIntegration}
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog

  test "publishes one complete application and tenant catalog snapshot" do
    store = start_supervised!({CatalogStore, []})
    application_client = discovery_client([{:ok, %{"tools" => [tool("clock")]}}])
    tenant_client = discovery_client([{:ok, %{"tools" => [tool("lookup_customer")]}}])

    configured = [
      configured_integration(:application, "utilities", "clock", application_client),
      configured_integration(
        {:tenant, "tenant-demo"},
        "records",
        "lookup_customer",
        tenant_client
      )
    ]

    assert {:ok, snapshot} = refresh(configured, store)
    assert {:ok, ^snapshot} = CatalogStore.snapshot(store)

    assert {:ok, application_tool} =
             IntegrationCatalog.resolve(snapshot, "another-tenant", "utilities", "clock")

    assert application_tool.scope == :application

    assert {:ok, tenant_tool} =
             IntegrationCatalog.resolve(snapshot, "tenant-demo", "records", "lookup_customer")

    assert tenant_tool.scope == {:tenant, "tenant-demo"}
  end

  test "retains the prior snapshot when any configured integration cannot be loaded" do
    store = start_supervised!({CatalogStore, []})
    old_client = discovery_client([{:ok, %{"tools" => [tool("clock")]}}])

    assert {:ok, old_snapshot} =
             refresh(
               [configured_integration(:application, "utilities", "clock", old_client)],
               store
             )

    replacement_client = discovery_client([{:ok, %{"tools" => [tool("clock")]}}])
    failed_client = discovery_client([{:error, :remote_error}])

    replacement =
      configured_integration(:application, "utilities", "clock", replacement_client,
        catalog_generation: "catalog-2"
      )

    failing =
      configured_integration(
        {:tenant, "tenant-demo"},
        "records",
        "lookup_customer",
        failed_client
      )

    assert {:error, {:integration_load_failed, failed_key, :discovery_failed}} =
             refresh([replacement, failing], store, maximum_concurrency: 1)

    assert failed_key == failing.connection_key
    assert {:ok, ^old_snapshot} = CatalogStore.snapshot(store)

    assert {:ok, old_tool} =
             IntegrationCatalog.resolve(old_snapshot, "tenant-demo", "utilities", "clock")

    assert old_tool.catalog_generation == "catalog-1"
  end

  test "rejects duplicate identities and unbounded concurrency before discovery" do
    store = start_supervised!({CatalogStore, []})
    client = discovery_client([{:ok, %{"tools" => [tool("clock")]}}])
    configured = configured_integration(:application, "utilities", "clock", client)

    assert {:error, :duplicate_integration} = refresh([configured, configured], store)

    assert {:error, :invalid_refresh_configuration} =
             refresh([configured], store, maximum_concurrency: 33)

    refute_receive {:test_remote_mcp_opened, _key, _config}
  end

  defp refresh(configured, store, options \\ []) do
    CatalogRefresh.run(
      configured,
      [
        catalog_store: store,
        connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
        protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
      ] ++ options
    )
  end

  defp configured_integration(scope, integration_id, tool_name, client, options \\ []) do
    {:ok, configured} =
      ConfiguredIntegration.new(
        scope: scope,
        integration_id: integration_id,
        configuration_generation: "configuration-1",
        credential_generation: "credential-1",
        catalog_generation: Keyword.get(options, :catalog_generation, "catalog-1"),
        allowed_tools: [tool_name],
        client_config: [test_client: client, test_observer: self()]
      )

    configured
  end

  defp discovery_client(responses) do
    start_supervised!(
      {Agent, fn -> %{discovery_calls: [], discovery_responses: responses} end},
      id: {Agent, make_ref()}
    )
  end

  defp tool(name) do
    %{
      "name" => name,
      "description" => "Controlled remote operation.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    }
  end
end
