defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefresherTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogRefresher,
    CatalogStore,
    ConfiguredIntegration,
    IntegrationCatalog
  }

  alias Vxpipe.CallEngine.RemoteMCP.CatalogRefresher.Options
  alias Vxpipe.CallEngine.TestRemoteMCPConfigurationSource

  test "refreshes immediately and periodically without blocking the catalog store" do
    configured = configured_integration("catalog-1")
    source = source({:ok, [configured]})
    store = start_supervised!({CatalogStore, []})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    refresher =
      start_supervised!(
        {CatalogRefresher,
         catalog_store: store,
         task_supervisor: task_supervisor,
         source: {TestRemoteMCPConfigurationSource, server: source},
         refresh_interval_ms: 10,
         stale_after_ms: 5_000,
         refresh_timeout_ms: 1_000,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient}
      )

    assert_receive {:test_remote_mcp_configuration_fetch, _task, 1}
    assert :ok = CatalogRefresher.refresh(refresher)
    assert_receive {:test_remote_mcp_configuration_fetch, _task, 2}

    assert {:ok, snapshot} = CatalogStore.snapshot(store)

    assert {:ok, tool} =
             IntegrationCatalog.resolve(snapshot, "tenant-demo", "records", "lookup_customer")

    assert tool.catalog_generation == "catalog-1"
    assert_receive {:test_remote_mcp_configuration_fetch, _task, 3}, 1_000
  end

  test "retains the last good catalog during failure, expires it, and recovers" do
    clock = start_supervised!({Agent, fn -> 1_000 end})
    source = source({:ok, [configured_integration("catalog-1")]})
    store = start_supervised!({CatalogStore, []})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    refresher =
      start_supervised!(
        {CatalogRefresher,
         catalog_store: store,
         task_supervisor: task_supervisor,
         source: {TestRemoteMCPConfigurationSource, server: source},
         refresh_interval_ms: 4_000,
         stale_after_ms: 5_000,
         refresh_timeout_ms: 1_000,
         clock: fn -> Agent.get(clock, & &1) end,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient}
      )

    assert :ok = CatalogRefresher.refresh(refresher)
    assert {:ok, first_snapshot} = CatalogStore.snapshot(store)
    assert {:ok, _tool} = resolve_tool(first_snapshot)

    TestRemoteMCPConfigurationSource.put_response(source, {:error, :vault_unavailable})
    Agent.update(clock, fn _current -> 5_999 end)

    assert {:error, :configuration_unavailable} = CatalogRefresher.refresh(refresher)
    assert :fresh = CatalogRefresher.check_staleness(refresher)
    assert {:ok, ^first_snapshot} = CatalogStore.snapshot(store)

    Agent.update(clock, fn _current -> 6_000 end)

    assert :expired = CatalogRefresher.check_staleness(refresher)
    assert {:ok, expired_snapshot} = CatalogStore.snapshot(store)
    assert {:error, :integration_not_configured} = resolve_tool(expired_snapshot)

    TestRemoteMCPConfigurationSource.put_response(
      source,
      {:ok, [configured_integration("catalog-2")]}
    )

    assert :ok = CatalogRefresher.refresh(refresher)

    assert %{expired?: false, last_outcome: :ok, refreshing?: false} =
             CatalogRefresher.status(refresher)

    assert {:ok, recovered_snapshot} = CatalogStore.snapshot(store)
    assert {:ok, recovered_tool} = resolve_tool(recovered_snapshot)
    assert recovered_tool.catalog_generation == "catalog-2"
  end

  test "keeps blocking configuration work outside callbacks and bounds it" do
    private_value = "private-refresher-option"
    source = source({:block, self()})
    store = start_supervised!({CatalogStore, []})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    options = [
      catalog_store: store,
      task_supervisor: task_supervisor,
      source:
        {TestRemoteMCPConfigurationSource, server: source, private_test_value: private_value},
      refresh_interval_ms: 10_000,
      stale_after_ms: 20_000,
      refresh_timeout_ms: 100
    ]

    assert {:ok, settings} = Options.new(options)
    refute inspect(settings) =~ private_value

    refresher = start_supervised!({CatalogRefresher, options})

    assert_receive {:test_remote_mcp_configuration_blocked, _task}
    assert %{refreshing?: true} = CatalogRefresher.status(refresher)
    assert {:ok, %IntegrationCatalog{}} = CatalogStore.snapshot(store)
    refute inspect(:sys.get_state(refresher)) =~ private_value

    assert {:error, :refresh_timeout} = CatalogRefresher.refresh(refresher, 1_000)

    assert %{last_outcome: {:error, :refresh_timeout}, refreshing?: false} =
             CatalogRefresher.status(refresher)
  end

  test "publishes a successful empty source as an intentional configuration removal" do
    source = source({:ok, [configured_integration("catalog-1")]})
    store = start_supervised!({CatalogStore, []})
    task_supervisor = start_supervised!({Task.Supervisor, []})

    refresher =
      start_supervised!(
        {CatalogRefresher,
         catalog_store: store,
         task_supervisor: task_supervisor,
         source: {TestRemoteMCPConfigurationSource, server: source},
         refresh_interval_ms: 10_000,
         stale_after_ms: 20_000,
         refresh_timeout_ms: 1_000,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient}
      )

    assert :ok = CatalogRefresher.refresh(refresher)
    assert {:ok, configured_snapshot} = CatalogStore.snapshot(store)
    assert {:ok, _tool} = resolve_tool(configured_snapshot)

    TestRemoteMCPConfigurationSource.put_response(source, {:ok, []})

    assert :ok = CatalogRefresher.refresh(refresher)
    assert {:ok, empty_snapshot} = CatalogStore.snapshot(store)
    assert {:error, :integration_not_configured} = resolve_tool(empty_snapshot)
    assert %{expired?: false, last_outcome: :ok} = CatalogRefresher.status(refresher)
  end

  defp source(response) do
    start_supervised!(
      {TestRemoteMCPConfigurationSource, observer: self(), response: response},
      id: {TestRemoteMCPConfigurationSource, make_ref()}
    )
  end

  defp configured_integration(catalog_generation) do
    client =
      start_supervised!(
        {Agent,
         fn ->
           %{
             discovery_calls: [],
             discovery_responses: List.duplicate({:ok, %{"tools" => [tool()]}}, 10)
           }
         end},
        id: {Agent, make_ref()}
      )

    {:ok, configured} =
      ConfiguredIntegration.new(
        scope: {:tenant, "tenant-demo"},
        integration_id: "records",
        configuration_generation: "configuration-1",
        credential_generation: "credential-1",
        catalog_generation: catalog_generation,
        allowed_tools: ["lookup_customer"],
        client_config: [test_client: client, test_observer: self()]
      )

    configured
  end

  defp resolve_tool(snapshot) do
    IntegrationCatalog.resolve(snapshot, "tenant-demo", "records", "lookup_customer")
  end

  defp tool do
    %{
      "name" => "lookup_customer",
      "description" => "Looks up one customer.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    }
  end
end
