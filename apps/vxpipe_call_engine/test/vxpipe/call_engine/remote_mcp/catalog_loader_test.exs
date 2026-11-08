defmodule Vxpipe.CallEngine.RemoteMCP.CatalogLoaderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogLoader, ConfiguredIntegration}
  alias Vxpipe.MCP.Catalog

  test "loads one tenant-scoped discovered integration without exposing private configuration" do
    client = discovery_client([{:ok, %{"tools" => [tool("lookup_customer")]}}])
    private_value = "private-catalog-loader-value"

    assert {:ok, configured} =
             ConfiguredIntegration.new(
               scope: {:tenant, "tenant-demo"},
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer"],
               client_config: [
                 test_client: client,
                 test_observer: self(),
                 private: private_value
               ],
               discovery_deadline_ms: 1_000,
               maximum_discovery_pages: 2,
               maximum_discovery_bytes: 10_000
             )

    refute inspect(configured) =~ private_value

    assert {:ok, integration} =
             CatalogLoader.load(configured,
               connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
               protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, key, opened_config}
    assert key.scope == {:tenant, "tenant-demo"}
    assert key.integration_id == "records"
    assert key.credential_generation == "credential-1"
    assert opened_config[:private] == private_value
    assert opened_config[:limits][:max_response_bytes] == 1_048_576
    assert opened_config[:limits][:max_stream_buffer_bytes] == 1_048_576

    assert [%{cursor: nil, timeout: timeout}] = discovery_calls(client)
    assert timeout in 1..1_000

    assert {:ok, %{"name" => "lookup_customer"}} =
             Catalog.fetch(integration.catalog, "lookup_customer")

    assert integration.allowed_tools == MapSet.new(["lookup_customer"])
    refute inspect(integration) =~ private_value
    assert_operation_closed(configured)
  end

  test "rejects a configured allowed tool that is absent from complete discovery" do
    client = discovery_client([{:ok, %{"tools" => [tool("different_tool")]}}])

    assert {:ok, configured} = configured_integration(client)

    assert {:error, :invalid_discovered_catalog} =
             CatalogLoader.load(configured,
               connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
               protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, _key, _opened_config}
    assert length(discovery_calls(client)) == 1
    assert_operation_closed(configured)
  end

  test "caller death closes an established discovery session" do
    client = discovery_client([{:wait, self(), {:ok, %{"tools" => [tool("lookup_customer")]}}}])
    {:ok, configured} = configured_integration(client)
    tasks = start_supervised!({Task.Supervisor, name: unique_task_name()})
    task = Task.Supervisor.async_nolink(tasks, fn -> load(configured) end)

    assert_receive {:test_catalog_discovery_waiting, worker, session}, 1_000
    assert_receive {:test_remote_mcp_open_options, _key, options}, 1_000
    host = Keyword.fetch!(options, :owner)
    monitors = for pid <- [worker, session, host], do: {pid, Process.monitor(pid)}
    Task.shutdown(task, :brutal_kill)

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end
  end

  test "loading from an exit-trapping host leaves its existing messages and flags intact" do
    previous = Process.flag(:trap_exit, true)
    client = discovery_client([{:ok, %{"tools" => [tool("lookup_customer")]}}])
    {:ok, configured} = configured_integration(client)
    sentinel = make_ref()
    send(self(), {:EXIT, self(), sentinel})

    try do
      assert {:ok, _integration} = load(configured)
      assert_operation_closed(configured)
      assert {:trap_exit, true} = Process.info(self(), :trap_exit)
      assert_receive {:EXIT, _self, ^sentinel}
      refute_receive {:EXIT, _owned_helper, _reason}, 0
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "a blocked opener shares the discovery deadline and leaves no partial session" do
    client = discovery_client([])
    {:ok, configured} = configured_integration(client)

    configured = %{
      configured
      | discovery_deadline_ms: 200,
        client_config: Keyword.put(configured.client_config, :test_gate_initialization, true)
    }

    tasks = start_supervised!({Task.Supervisor, name: unique_task_name()})
    task = Task.Supervisor.async_nolink(tasks, fn -> load(configured) end)
    assert_receive {:test_remote_mcp_initializing, opener}, 1_000
    monitor = Process.monitor(opener)
    assert {:error, :discovery_timed_out} = Task.await(task, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^opener, _reason}, 0
    assert_operation_closed(configured)
    assert discovery_calls(client) == []
  end

  test "one operation deadline bounds a blocked discovery and closes its session" do
    client = discovery_client([{:wait, self(), {:ok, %{"tools" => [tool("lookup_customer")]}}}])
    {:ok, configured} = configured_integration(client)
    configured = %{configured | discovery_deadline_ms: 200}
    tasks = start_supervised!({Task.Supervisor, name: unique_task_name()})
    task = Task.Supervisor.async_nolink(tasks, fn -> load(configured) end)

    assert_receive {:test_catalog_discovery_waiting, worker, session}, 1_000
    monitors = for pid <- [worker, session], do: {pid, Process.monitor(pid)}
    assert {:error, :discovery_timed_out} = Task.await(task, 2_000)

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 0
    end

    assert_operation_closed(configured)
  end

  test "rejects malformed private configuration before discovery" do
    assert {:error, :invalid_configured_integration} =
             ConfiguredIntegration.new(
               scope: :application,
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer", "lookup_customer"],
               client_config: [limits: :unbounded]
             )

    assert {:error, :invalid_configured_integration} =
             ConfiguredIntegration.new(
               scope: :application,
               integration_id: "records",
               configuration_generation: "configuration-1",
               credential_generation: "credential-1",
               catalog_generation: "catalog-1",
               allowed_tools: ["lookup_customer"],
               client_config: [:not_a_keyword_entry]
             )
  end

  test "rejecting a foreign provider handle leaves its actual owner's session intact" do
    client = discovery_client([])
    {:ok, configured} = configured_integration(client)
    host = Vxpipe.CallEngine.RemoteMCPFixture.session_supervisor!()

    {:ok, connection} =
      Vxpipe.MCP.Connections.open(
        configured.connection_key,
        [endpoint: "https://fixture.example.test/mcp"],
        owner: host,
        runtime: Vxpipe.CallEngine.TestRemoteMCPClient,
        runtime_options: [test_client: client]
      )

    configured = %{configured | client_config: [foreign_connection: connection]}

    assert {:error, :connection_failed} =
             CatalogLoader.load(configured,
               connection_provider: Vxpipe.CallEngine.ForeignMCPConnectionProvider,
               protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
             )

    assert {:ok, ^connection} =
             Vxpipe.MCP.Connections.lookup(configured.connection_key, owner: host)

    assert discovery_calls(client) == []
  end

  defp configured_integration(client) do
    ConfiguredIntegration.new(
      scope: :application,
      integration_id: "records",
      configuration_generation: "configuration-1",
      credential_generation: "credential-1",
      catalog_generation: "catalog-1",
      allowed_tools: ["lookup_customer"],
      client_config: [test_client: client, test_observer: self()]
    )
  end

  defp load(configured) do
    CatalogLoader.load(configured,
      connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
      protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
    )
  end

  defp assert_operation_closed(configured) do
    assert_receive {:test_remote_mcp_open_options, _key, options}
    host = Keyword.fetch!(options, :owner)
    monitor = Process.monitor(host)
    assert_receive {:DOWN, ^monitor, :process, ^host, _reason}
    assert :error = Vxpipe.MCP.Connections.lookup(configured.connection_key)
  end

  defp unique_task_name do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, make_ref()}}}
  end

  defp discovery_client(responses) do
    start_supervised!(
      {Agent,
       fn ->
         %{
           discovery_calls: [],
           discovery_responses: responses
         }
       end},
      id: {Agent, make_ref()}
    )
  end

  defp discovery_calls(client), do: Agent.get(client, & &1.discovery_calls)

  defp tool(name) do
    %{
      "name" => name,
      "description" => "Looks up one customer.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"],
        "additionalProperties" => false
      }
    }
  end
end
