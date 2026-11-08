defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationOwnerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPFixture
  alias Vxpipe.MCP.{Connections, CredentialLeases}

  setup do
    %{session_supervisor: RemoteMCPFixture.session_supervisor!()}
  end

  test "waiting for the room budget respects the original startup deadline", %{
    session_supervisor: sessions
  } do
    client = client!([])
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")
    started = System.monotonic_time(:millisecond)

    assert {:error, _reason} =
             start_supervised(
               {IntegrationOwner,
                activation_id: "budget-wait",
                session_supervisor: sessions,
                lifecycle_owner: self(),
                initialization: {self(), started + 100},
                tools: %{"customer_lookup" => binding},
                integrations: RemoteMCPFixture.source!(catalog),
                connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
             )

    assert System.monotonic_time(:millisecond) - started < 400
    refute_received {:test_remote_mcp_opened, _, _}
  end

  test "preparer death interrupts waiting for the room budget", %{session_supervisor: sessions} do
    client = client!([])
    preparer = start_supervised!({Agent, fn -> :preparing end}, id: :budget_preparer)
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")

    supervisor =
      start_supervised!({DynamicSupervisor, name: unique_name(), strategy: :one_for_one})

    tasks = start_supervised!({Task.Supervisor, name: unique_name()})
    authority = self()

    source = RemoteMCPFixture.source!(catalog)

    starter =
      Task.Supervisor.async_nolink(tasks, fn ->
        DynamicSupervisor.start_child(
          supervisor,
          {IntegrationOwner,
           activation_id: "budget-cancel",
           session_supervisor: sessions,
           lifecycle_owner: authority,
           initialization: {preparer, System.monotonic_time(:millisecond) + 5_000},
           tools: %{"customer_lookup" => binding},
           integrations: source,
           connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
           protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
        )
      end)

    assert_receive {:"$gen_call", _from, {:mcp_initialization_budget, _, ^preparer, _}}, 1_000
    assert :ok = stop_supervised(:budget_preparer)
    assert {:ok, {:error, _reason}} = Task.yield(starter, 400)
    refute_received {:test_remote_mcp_opened, _, _}
  end

  test "caller cancellation rolls back an earlier session while the next provider is blocked", %{
    session_supervisor: sessions
  } do
    client = client!([])
    lifecycle = start_supervised!({Agent, fn -> :running end}, id: :startup_lifecycle)
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")
    {:ok, good} = Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.checkout(catalog, binding.remote)

    held = %{
      good
      | integration_id: "held",
        client_config: Keyword.put(good.client_config, :test_gate_initialization, true)
    }

    {:ok, catalog} =
      Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-demo" => %{"records" => good, "held" => held}}
      )

    {:ok, held_remote} =
      Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.resolve(
        catalog,
        "tenant-demo",
        "held",
        "lookup_customer"
      )

    bindings = %{
      "a_held" => %{binding | name: "a_held", remote: held_remote},
      "z_ready" => %{binding | name: "z_ready"}
    }

    supervisor =
      start_supervised!({DynamicSupervisor, name: unique_name(), strategy: :one_for_one})

    tasks = start_supervised!({Task.Supervisor, name: unique_name()})

    source = RemoteMCPFixture.source!(catalog)

    starter =
      Task.Supervisor.async_nolink(tasks, fn ->
        DynamicSupervisor.start_child(
          supervisor,
          {IntegrationOwner,
           activation_id: "cancel-partial",
           session_supervisor: sessions,
           lifecycle_owner: lifecycle,
           tools: bindings,
           integrations: source,
           connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
           protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
        )
      end)

    assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
    [{_, integration, :supervisor, _}] = DynamicSupervisor.which_children(sessions)
    monitor = Process.monitor(integration)
    on_exit(fn -> send(initializer, :test_remote_mcp_initialized) end)
    assert :ok = stop_supervised(:startup_lifecycle)
    assert {:error, _reason} = Task.await(starter, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^integration, _reason}, 1_000
    assert DynamicSupervisor.count_children(sessions).active == 0
  end

  test "a failed second integration rolls back the standalone host's partial startup", %{
    session_supervisor: sessions
  } do
    client = client!([])
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")
    {:ok, good} = Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.checkout(catalog, binding.remote)

    failed = %{
      good
      | integration_id: "failed",
        client_config: Keyword.put(good.client_config, :test_fail_open, true)
    }

    {:ok, catalog} =
      Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.new(
        application: %{},
        tenants: %{"tenant-demo" => %{"records" => good, "failed" => failed}}
      )

    {:ok, failed_remote} =
      Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog.resolve(
        catalog,
        "tenant-demo",
        "failed",
        "lookup_customer"
      )

    tools = %{
      "a_failure" => %{binding | name: "a_failure", remote: failed_remote},
      "z_success" => %{binding | name: "z_success"}
    }

    assert {:error, _reason} =
             start_supervised(
               {IntegrationOwner,
                activation_id: "partial-startup",
                session_supervisor: sessions,
                tools: tools,
                integrations: RemoteMCPFixture.source!(catalog),
                connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
             )

    assert_receive {:test_mcp_partial_children, [{_, integration, :supervisor, _}]}
    monitor = Process.monitor(integration)
    assert_receive {:DOWN, ^monitor, :process, ^integration, _reason}, 1_000
    assert DynamicSupervisor.count_children(sessions).active == 0
  end

  for type <- [:participant_transfer, :platform] do
    @binding_type type
    test "allows the built-in #{@binding_type} tool beside pinned MCP bindings", %{
      session_supervisor: sessions
    } do
      client = client!([])
      {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")

      transfer = %Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding{
        name: "transfer",
        type: @binding_type,
        conversation_mode: :non_blocking,
        action: nil,
        remote: nil
      }

      assert {:ok, _owner} =
               start_supervised(
                 {IntegrationOwner,
                  activation_id: "mcp-with-transfer",
                  session_supervisor: sessions,
                  tools: %{"customer_lookup" => binding, "transfer" => transfer},
                  integrations: RemoteMCPFixture.source!(catalog),
                  connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                  protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
               )
    end
  end

  test "withholds readiness until scoped connection initialization finishes without invoking tools",
       %{session_supervisor: sessions} do
    client = client!([])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private",
        client_config: [
          test_client: client,
          test_observer: self(),
          test_gate_initialization: true,
          private: "private-readiness-sentinel"
        ]
      )

    supervisor =
      start_supervised!({DynamicSupervisor, name: unique_name(), strategy: :one_for_one})

    tasks = start_supervised!({Task.Supervisor, name: unique_name()})
    name = unique_name()

    source = RemoteMCPFixture.source!(catalog)

    starter =
      Task.Supervisor.async_nolink(tasks, fn ->
        DynamicSupervisor.start_child(
          supervisor,
          {IntegrationOwner,
           session_supervisor: sessions,
           activation_id: "readiness-activation",
           participant_id: "support-agent",
           tools: %{"customer_lookup" => binding},
           integrations: source,
           name: name,
           connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
           protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
        )
      end)

    assert_receive {:test_remote_mcp_initializing, initializer}
    observer = self()

    query =
      Task.Supervisor.async_nolink(tasks, fn ->
        result = IntegrationOwner.readiness(name)
        send(observer, {:readiness_result, result})
        result
      end)

    refute_receive {:readiness_result, _result}
    send(initializer, :test_remote_mcp_initialized)
    assert {:ok, owner} = Task.await(starter)
    assert {:ok, resource, :ready} = Task.await(query)
    assert resource.instance == owner
    assert resource.scope == {:participant, "support-agent"}
    assert resource.binding == "readiness-activation"
    assert resource.kind == :remote_tools
    assert is_reference(resource.generation)
    assert byte_size(resource.configuration) == 32
    refute inspect(resource) =~ "private-readiness-sentinel"
    assert {:ok, ^resource, :ready} = IntegrationOwner.readiness(owner)
    assert invocations(client) == []
  end

  test "conflicting alias policies fail before any integration is opened", %{
    session_supervisor: sessions
  } do
    client = client!([])
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")
    source = RemoteMCPFixture.source!(catalog)

    for field <- [:invocation_deadline_ms, :maximum_result_bytes] do
      policy = Map.update!(binding.remote, field, &(&1 + 1))
      conflict = %{binding | name: "conflicting_alias", remote: policy}

      assert {:error, _} =
               start_supervised(
                 {IntegrationOwner,
                  activation_id: "conflicting-policy",
                  session_supervisor: sessions,
                  tools: %{"customer_lookup" => binding, "conflicting_alias" => conflict},
                  integrations: source,
                  connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                  protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
               )

      assert DynamicSupervisor.count_children(sessions).active == 0
      refute_received {:test_remote_mcp_opened, _, _}
    end
  end

  test "opens the scoped generation and invokes the pinned remote operation", %{
    session_supervisor: sessions
  } do
    client = client!([{:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}])
    private_value = "private-runtime-sentinel"

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), private_value, maximum_result_bytes: 65_536)

    owner =
      start_supervised!(
        {IntegrationOwner,
         session_supervisor: sessions,
         activation_id: "activation-one",
         tools: %{"customer_lookup" => binding},
         integrations: RemoteMCPFixture.source!(catalog),
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, key, opened_config}
    assert key.scope == {:tenant, "tenant-demo"}
    assert key.integration_id == "records"
    assert key.credential_generation == "credential-1"
    assert opened_config[:private] == private_value

    limits = Keyword.fetch!(opened_config, :limits)
    assert limits[:max_response_bytes] == 65_536
    assert limits[:max_stream_buffer_bytes] == 65_536
    refute inspect(:sys.get_state(owner)) =~ private_value

    assert {:error, :invalid_arguments} =
             IntegrationOwner.execute(owner, "customer_lookup", %{"customer_id" => 42})

    assert invocations(client) == []

    arguments = %{"customer_id" => "customer-42"}

    assert {:ok, %{"content" => [%{"text" => "found", "type" => "text"}]}} =
             IntegrationOwner.execute(owner, "customer_lookup", arguments)

    assert [%{name: "lookup_customer", arguments: ^arguments, timeout: timeout}] =
             invocations(client)

    assert timeout in 1..12_000
    assert {:error, :unknown_tool} = IntegrationOwner.execute(owner, "not_enabled", %{})
  end

  test "withholds a remote response beyond the pinned result limit", %{
    session_supervisor: sessions
  } do
    client = client!([{:ok, %{"content" => [String.duplicate("x", 100)]}}])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private", maximum_result_bytes: 32)

    owner =
      start_supervised!(
        {IntegrationOwner,
         session_supervisor: sessions,
         activation_id: "activation-limit",
         tools: %{"customer_lookup" => binding},
         integrations: RemoteMCPFixture.source!(catalog),
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}

    assert {:error, :invalid_result} =
             IntegrationOwner.execute(
               owner,
               "customer_lookup",
               %{"customer_id" => "customer-42"}
             )

    assert length(invocations(client)) == 1
  end

  test "fails the binding owner closed when its protocol client exits", %{
    session_supervisor: sessions
  } do
    client = client!([])
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")

    owner =
      start_supervised!(
        {IntegrationOwner,
         session_supervisor: sessions,
         activation_id: "activation-connection-loss",
         participant_id: "support-agent",
         tools: %{"customer_lookup" => binding},
         integrations: RemoteMCPFixture.source!(catalog),
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}
    client_monitor = Process.monitor(client)
    owner_monitor = Process.monitor(owner)
    assert {:ok, _resource, :ready} = IntegrationOwner.readiness(owner)

    assert :ok = stop_supervised(Agent)
    assert_receive {:DOWN, ^client_monitor, :process, ^client, _reason}, 1_000
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :connection_lost}, 1_000
    assert {:error, :unavailable} = IntegrationOwner.readiness(owner)
  end

  test "ends a revoked credential lease with its binding owner", %{session_supervisor: sessions} do
    generation = "credential-revoked-#{System.unique_integer([:positive, :monotonic])}"
    client = client!([])

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "private", credential_generation: generation)

    owner =
      start_supervised!(
        {IntegrationOwner,
         session_supervisor: sessions,
         activation_id: "activation-revoked-credential",
         participant_id: "support-agent",
         tools: %{"customer_lookup" => binding},
         integrations: RemoteMCPFixture.source!(catalog),
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, key, _config}
    assert CredentialLeases.active_count(key) == 1
    assert {:ok, _resource, :ready} = IntegrationOwner.readiness(owner)

    owner_monitor = Process.monitor(owner)
    assert :ok = Connections.revoke(key)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :credential_revoked}, 1_000
    assert CredentialLeases.active_count(key) == 0
    assert {:error, :unavailable} = IntegrationOwner.readiness(owner)

    assert {:error, {:credential_revoked, _child}} =
             start_supervised(
               {IntegrationOwner,
                session_supervisor: sessions,
                activation_id: "activation-revoked-credential-reuse",
                tools: %{"customer_lookup" => binding},
                integrations: RemoteMCPFixture.source!(catalog),
                connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
                protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
             )

    refute_receive {:test_remote_mcp_opened, ^key, _config}
  end

  defp client!(responses) do
    start_supervised!({Agent, fn -> %{responses: responses, invocations: []} end})
  end

  defp invocations(client), do: Agent.get(client, & &1.invocations)

  defp unique_name, do: {:global, {__MODULE__, make_ref()}}
end
