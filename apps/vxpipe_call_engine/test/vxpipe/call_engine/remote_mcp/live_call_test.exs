defmodule Vxpipe.CallEngine.RemoteMCP.LiveCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, PendingInvocation, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    RemoteMCPFixture,
    Error,
    TestAgentRuntimeModelProvider,
    TestRemoteMCPConnectionProvider,
    TestRemoteMCPProtocolClient
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ToolCallCompleted, ToolCallStarted}
  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.CallVariables.UpdateSnapshot
  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationCatalog}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:fixture, {TestAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  @tag :embedded_restart
  @tag :capture_log
  test "room and activation restart state retains a source instead of embedded credentials" do
    marker = "synthetic-embedded-restart-credential"
    client = start_supervised!({Agent, fn -> %{responses: [], invocations: []} end})
    {catalog, _binding} = RemoteMCPFixture.binding!(client, self(), marker)
    store = start_supervised!(CatalogStore)
    :ok = CatalogStore.publish(store, catalog)
    plan = compile_plan(store)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
    participant = Map.fetch!(plan.participants, "reception")

    for key <- [
          {:room_incarnation, plan.tenant_id, plan.room_id, room.incarnation_id},
          {plan.tenant_id, plan.room_id},
          {:participant_supervisor, plan.tenant_id, plan.room_id, participant.participant_id},
          {:agent_activation, participant.activation_id, :supervisor}
        ] do
      [{process, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key)
      refute :erlang.term_to_binary(:sys.get_state(process)) =~ marker
    end
  end

  for change <- [:changed, :unavailable] do
    @tag embedded_restart: true, source_change: change, capture_log: true
    test "activation recovery fails closed when its catalog source is #{change}", context do
      client = start_supervised!({Agent, fn -> %{responses: [], invocations: []} end})

      {catalog, _binding} =
        RemoteMCPFixture.binding!(client, self(), "private-recovery",
          credential_generation: unique_id("credential")
        )

      store = start_supervised!(CatalogStore)
      :ok = CatalogStore.publish(store, catalog)
      plan = compile_plan(store)

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan,
                 mcp_catalog_store: store,
                 remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
                 remote_mcp_protocol_client: TestRemoteMCPProtocolClient
               )

      on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
      attach_caller(plan, room)
      assert_receive {:test_remote_mcp_opened, key, _config}
      activation = Map.fetch!(plan.participants, "reception").activation_id

      [{supervisor, _}] =
        Registry.lookup(
          Vxpipe.CallEngine.RoomRegistry,
          {:agent_activation, activation, :supervisor}
        )

      monitor = Process.monitor(supervisor)

      host =
        Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
          activation,
          :remote_mcp_sessions
        )

      assert {:ok, connection} = Vxpipe.MCP.Connections.lookup(key, owner: host)

      case context.source_change do
        :changed ->
          {:ok, empty} = IntegrationCatalog.new([])
          :ok = CatalogStore.publish(store, empty)

        :unavailable ->
          stop_supervised!(CatalogStore)
      end

      Process.exit(Vxpipe.MCP.Connection.client(connection), :kill)
      assert_receive {:DOWN, ^monitor, :process, ^supervisor, _reason}, 1_000
      refute_receive {:test_remote_mcp_opened, ^key, _config}, 100
    end
  end

  @tag :integration
  @tag :capture_log
  test "transfer and re-entry prepare independent wire sessions before retiring the source" do
    server =
      start_supervised!(
        {Vxpipe.CallEngine.RemoteMCPWireServer, owner: self(), hold_initialization: true}
      )

    {integrations, binding} =
      RemoteMCPFixture.binding!(nil, self(), "unused",
        credential_generation: unique_id("credential"),
        client_config: [
          endpoint: Vxpipe.CallEngine.RemoteMCPWireServer.endpoint(server),
          use_sse: false
        ]
      )

    plan = compile_plan(integrations, transfer?: true, transfer_timeout_ms: 5_000)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               mcp_catalog_store: RemoteMCPFixture.source!(integrations),
               remote_mcp_connection_provider: Vxpipe.CallEngine.RemoteMCPWireConnectionProvider
             )

    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
    assert_receive {:remote_mcp_wire_initialization_held, initializer, reference}, 1_000
    send(initializer, {:release_remote_mcp_initialization, reference})
    Vxpipe.CallEngine.TestCallStartup.await_prepared(plan)
    caller = attach_caller(plan, room)
    assert_receive {:remote_mcp_wire_initialized, initial_session}

    {:ok, key} =
      Vxpipe.MCP.ConnectionKey.new(
        scope: :tenant,
        tenant_id: plan.tenant_id,
        integration_id: binding.remote.integration_id,
        credential_generation: binding.remote.credential_generation
      )

    {initial_activation, initial_connection} = active_mcp(plan, key, "reception")

    {_activation, _connection, _session} =
      Enum.reduce(
        ["records", "reception"],
        {initial_activation, initial_connection, initial_session},
        fn destination, {old_activation, old_connection, old_session} ->
          client = Vxpipe.MCP.Connection.client(old_connection)
          monitor = Process.monitor(client)
          {caller_participant, connection_id} = caller
          command = send_text(plan, room, caller_participant, connection_id, "Transfer me.")
          command_id = command.id

          assert_receive {:test_agent_runtime_stream, provider,
                          %{correlation: %{command_id: ^command_id}}},
                         1_000

          id = "transfer-#{destination}"
          reply_with_tool(provider, id, "transfer", %{"destination" => destination})
          assert_receive {:remote_mcp_wire_initialization_held, initializer, reference}, 1_000

          assert {:ok, ^old_connection} =
                   Vxpipe.MCP.Connections.lookup(key,
                     owner: Vxpipe.MCP.Connection.session_owner(old_connection)
                   )

          refute_received {:DOWN, ^monitor, :process, ^client, _reason}
          refute_received {:remote_mcp_wire_delete, [^old_session]}
          send(initializer, {:release_remote_mcp_initialization, reference})
          assert_receive {:remote_mcp_wire_initialized, new_session}, 1_000
          refute new_session in [old_session, initial_session]
          assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 2_000
          assert_receive {:DOWN, ^monitor, :process, ^client, _reason}, 2_000
          assert_receive {:remote_mcp_wire_delete, [^old_session]}, 1_000
          {new_activation, new_connection} = active_mcp(plan, key, destination)
          refute new_activation in [old_activation, initial_activation]

          refute Vxpipe.MCP.Connection.session_owner(new_connection) ==
                   Vxpipe.MCP.Connection.session_owner(old_connection)

          assert :ok = Vxpipe.MCP.Connections.close(old_connection)
          wire_tool_turn(plan, room, caller, "tool-#{destination}")
          assert_receive {:remote_mcp_wire_session_request, "tools/call", [^new_session]}, 1_000
          {new_activation, new_connection, new_session}
        end
      )
  end

  @tag :integration
  @tag :capture_log
  test "hangup retires one real MCP session while another admitted call still uses its own" do
    server = start_supervised!({Vxpipe.CallEngine.RemoteMCPWireServer, owner: self()})

    {integrations, binding} =
      RemoteMCPFixture.binding!(nil, self(), "unused",
        credential_generation: unique_id("credential"),
        client_config: [
          endpoint: Vxpipe.CallEngine.RemoteMCPWireServer.endpoint(server),
          use_sse: false
        ]
      )

    first_plan = compile_plan(integrations)
    second_plan = compile_plan(integrations)

    runtime = [
      mcp_catalog_store: RemoteMCPFixture.source!(integrations),
      remote_mcp_connection_provider: Vxpipe.CallEngine.RemoteMCPWireConnectionProvider
    ]

    assert {:ok, first} = Vxpipe.CallEngine.TestCallStartup.start_call(first_plan, runtime)
    first_caller = attach_caller(first_plan, first)
    assert_receive {:remote_mcp_wire_initialized, first_session}
    assert {:ok, second} = Vxpipe.CallEngine.TestCallStartup.start_call(second_plan, runtime)
    second_caller = attach_caller(second_plan, second)
    assert_receive {:remote_mcp_wire_initialized, second_session}
    refute first_session == second_session

    on_exit(fn ->
      CallEngine.end_call(first_plan.tenant_id, first_plan.room_id, first.incarnation_id)
      CallEngine.end_call(second_plan.tenant_id, second_plan.room_id, second.incarnation_id)
    end)

    {:ok, key} =
      Vxpipe.MCP.ConnectionKey.new(
        scope: :tenant,
        tenant_id: first_plan.tenant_id,
        integration_id: binding.remote.integration_id,
        credential_generation: binding.remote.credential_generation
      )

    first_activation = Map.fetch!(first_plan.participants, "reception").activation_id
    second_activation = Map.fetch!(second_plan.participants, "reception").activation_id

    first_host =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
        first_activation,
        :remote_mcp_sessions
      )

    second_host =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
        second_activation,
        :remote_mcp_sessions
      )

    assert {:ok, first_connection} = Vxpipe.MCP.Connections.lookup(key, owner: first_host)
    assert {:ok, second_connection} = Vxpipe.MCP.Connections.lookup(key, owner: second_host)
    refute first_connection == second_connection

    wire_tool_turn(first_plan, first, first_caller, "first-call")
    assert_receive {:remote_mcp_wire_session_request, "tools/call", [^first_session]}
    first_client = Vxpipe.MCP.Connection.client(first_connection)
    monitor = Process.monitor(first_client)

    assert {:ok, completion} =
             CallEngine.monitor_room_completion(
               first_plan.tenant_id,
               first_plan.room_id,
               first.incarnation_id
             )

    assert :ok =
             CallEngine.end_call(first_plan.tenant_id, first_plan.room_id, first.incarnation_id)

    assert_receive {:DOWN, ^completion, :process, _room, _reason}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^first_client, _reason}, 1_000
    assert_receive {:remote_mcp_wire_delete, [^first_session]}, 1_000

    assert {:ok, ^second_connection} = Vxpipe.MCP.Connections.lookup(key, owner: second_host)
    wire_tool_turn(second_plan, second, second_caller, "second-call")
    assert_receive {:remote_mcp_wire_session_request, "tools/call", [^second_session]}
  end

  @tag :integration
  @tag :capture_log
  test "the room remains responsive while its retired source's DELETE is held" do
    server = start_supervised!({Vxpipe.MCP.SessionHTTPFixture, owner: self(), hold_delete: true})

    {integrations, _binding} =
      RemoteMCPFixture.binding!(nil, self(), "unused",
        credential_generation: unique_id("credential"),
        client_config: [endpoint: Vxpipe.MCP.SessionHTTPFixture.endpoint(server), use_sse: false]
      )

    plan = compile_plan(integrations, transfer?: true, transfer_timeout_ms: 5_000)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               mcp_catalog_store: RemoteMCPFixture.source!(integrations),
               remote_mcp_connection_provider: Vxpipe.CallEngine.RemoteMCPWireConnectionProvider
             )

    {caller, connection_id} = attach_caller(plan, room)
    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    command = send_text(plan, room, caller, connection_id, "Transfer me.")
    command_id = command.id

    assert_receive {:test_agent_runtime_stream, provider,
                    %{correlation: %{command_id: ^command_id}}},
                   1_000

    reply_with_tool(provider, "held-source-delete", "transfer", %{"destination" => "records"})
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "held-source-delete"}}, 2_000
    assert_receive {:session_http_held, :delete, _peer}, 1_000
    assert GenServer.call(authority, :input_admission, 150) == :open
    assert_receive {:session_http_closed, :delete, {:error, :closed}}, 2_000
  end

  for retirement <- [:hangup, :room_authority_kill] do
    @tag :integration
    @tag :capture_log
    test "#{retirement} closes held POST and GET sockets with all session descendants" do
      server = start_supervised!({Vxpipe.MCP.SessionHTTPFixture, owner: self()})

      {integrations, _binding} =
        RemoteMCPFixture.binding!(nil, self(), "unused",
          credential_generation: unique_id("credential"),
          client_config: [endpoint: Vxpipe.MCP.SessionHTTPFixture.endpoint(server)]
        )

      plan = compile_plan(integrations)

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan,
                 mcp_catalog_store: RemoteMCPFixture.source!(integrations),
                 remote_mcp_connection_provider: Vxpipe.CallEngine.RemoteMCPWireConnectionProvider
               )

      on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
      {caller, connection_id} = attach_caller(plan, room)
      assert_receive {:session_http_held, :get, _peer}, 1_000
      send_text(plan, room, caller, connection_id, "Find a customer.")
      assert_receive {:test_agent_runtime_stream, provider, _request}, 1_000
      reply_with_tool(provider, "held-before-retirement")
      assert_receive {:session_http_held, :post, _peer}, 1_000
      activation = Map.fetch!(plan.participants, "reception").activation_id

      host =
        Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
          activation,
          :remote_mcp_sessions
        )

      monitors = monitor_session_tree(host)

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 plan.tenant_id,
                 plan.room_id,
                 room.incarnation_id
               )

      case unquote(retirement) do
        :hangup ->
          assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)

        :room_authority_kill ->
          [{authority, _}] =
            Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

          Process.exit(authority, :kill)
      end

      assert_receive {:DOWN, ^completion, :process, _room, _reason}, 2_000

      for {pid, monitor} <- monitors do
        assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
      end

      assert_receive {:session_http_closed, :post, {:error, :closed}}, 1_000
      assert_receive {:session_http_closed, :get, {:error, :closed}}, 1_000
      refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: "held-before-retirement"}}
    end
  end

  for cancellation <- [:hangup, :preparer_death, :binding_owner_kill, :readiness_deadline] do
    @tag :capture_log
    test "#{cancellation} removes an activation blocked in MCP initialization" do
      client = start_supervised!({Agent, fn -> %{responses: [], invocations: []} end})

      {integrations, _binding} =
        RemoteMCPFixture.binding!(client, self(), "private",
          credential_generation: unique_id("credential"),
          client_config: [
            test_client: client,
            test_observer: self(),
            test_gate_initialization: true
          ]
        )

      plan = compile_plan(integrations)
      readiness_timeout = if unquote(cancellation) == :readiness_deadline, do: 500, else: 30_000

      assert {:ok, room} =
               CallEngine.start_call(plan,
                 call_lifecycle: [readiness_timeout_ms: readiness_timeout],
                 mcp_catalog_store: RemoteMCPFixture.source!(integrations),
                 remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
                 remote_mcp_protocol_client: TestRemoteMCPProtocolClient
               )

      assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
      initializer_monitor = Process.monitor(initializer)

      assert {:ok, completion} =
               CallEngine.monitor_room_completion(
                 plan.tenant_id,
                 plan.room_id,
                 room.incarnation_id
               )

      on_exit(fn ->
        send(initializer, :test_remote_mcp_initialized)
        CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
      end)

      case unquote(cancellation) do
        :hangup ->
          assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)

        :preparer_death ->
          [{authority, _}] =
            Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

          preparer = :sys.get_state(authority).startup.task.pid
          Process.exit(preparer, :kill)

        :binding_owner_kill ->
          activation = Map.fetch!(plan.participants, "reception").activation_id

          owner =
            Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
              activation,
              :remote_mcp_owner
            )

          Process.exit(owner, :kill)

        :readiness_deadline ->
          [{authority, _}] =
            Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

          lifecycle = :sys.get_state(authority).call_lifecycle
          deadline = Vxpipe.CallEngine.CallLifecycle.readiness_deadline(lifecycle)
          assert_receive {:test_remote_mcp_open_options, _key, options}
          assert Keyword.fetch!(options, :deadline) == deadline
      end

      assert_receive {:DOWN, ^initializer_monitor, :process, ^initializer, _reason}, 1_500
      assert_receive {:DOWN, ^completion, :process, _room_supervisor, _reason}, 1_500
    end
  end

  @tag :capture_log
  test "a committed call recovers an MCP session after its original readiness deadline" do
    client = start_supervised!({Agent, fn -> %{responses: [], invocations: []} end})

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private",
        credential_generation: unique_id("credential")
      )

    plan = compile_plan(integrations)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               call_lifecycle: [readiness_timeout_ms: 500],
               mcp_catalog_store: RemoteMCPFixture.source!(integrations),
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    attach_caller(plan, room)
    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
    assert_receive {:test_remote_mcp_opened, key, _config}

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    deadline =
      Vxpipe.CallEngine.CallLifecycle.readiness_deadline(:sys.get_state(authority).call_lifecycle)

    timer = make_ref()
    Process.send_after(self(), timer, max(deadline - System.monotonic_time(:millisecond), 0) + 10)
    assert_receive ^timer, 1_000

    activation = Map.fetch!(plan.participants, "reception").activation_id

    host =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(activation, :remote_mcp_sessions)

    assert {:ok, original} = Vxpipe.MCP.Connections.lookup(key, owner: host)
    protocol_client = Vxpipe.MCP.Connection.client(original)
    monitor = Process.monitor(protocol_client)
    Process.exit(protocol_client, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^protocol_client, _reason}, 1_000
    assert_receive {:test_remote_mcp_opened, ^key, _config}, 1_000

    owner = Vxpipe.CallEngine.AgentActivationSupervisor.child_ref(activation, :remote_mcp_owner)

    assert {:ok, _resource, :ready} =
             Vxpipe.CallEngine.RemoteMCP.IntegrationOwner.readiness(owner)

    replacement_host =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(activation, :remote_mcp_sessions)

    refute replacement_host == host
    assert {:ok, replacement} = Vxpipe.MCP.Connections.lookup(key, owner: replacement_host)
    refute Vxpipe.MCP.Connection.client(replacement) == protocol_client
  end

  @tag :capture_log
  test "transfer timeout removes its blocked MCP destination and preserves the source" do
    response = {:ok, %{"content" => [%{"type" => "text", "text" => "source usable"}]}}
    client = start_supervised!({Agent, fn -> %{responses: [response], invocations: []} end})

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private",
        credential_generation: unique_id("credential"),
        client_config: [
          test_client: client,
          test_observer: self(),
          test_gate_initialization: true
        ]
      )

    plan = compile_plan(integrations, transfer?: true)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               mcp_catalog_store: RemoteMCPFixture.source!(integrations),
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    assert_receive {:test_remote_mcp_initializing, source_initializer}, 1_000
    send(source_initializer, :test_remote_mcp_initialized)
    Vxpipe.CallEngine.TestCallStartup.await_prepared(plan)
    {caller, connection_id} = attach_caller(plan, room)

    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)
    activation = Map.fetch!(plan.participants, "reception").activation_id

    source =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(activation, :remote_mcp_owner)

    source_monitor = Process.monitor(source)

    send_text(plan, room, caller, connection_id, "Transfer me.")
    assert_receive {:test_agent_runtime_stream, provider, _request}
    reply_with_tool(provider, "transfer-held-mcp", "transfer", %{"destination" => "records"})
    assert_receive {:test_remote_mcp_initializing, destination_initializer}, 1_000
    destination_monitor = Process.monitor(destination_initializer)
    on_exit(fn -> send(destination_initializer, :test_remote_mcp_initialized) end)

    assert_receive {:DOWN, ^destination_monitor, :process, ^destination_initializer, _reason},
                   2_000

    assert {:ok, %{"content" => [%{"text" => "source usable", "type" => "text"}]}} =
             Vxpipe.CallEngine.RemoteMCP.IntegrationOwner.execute(
               source,
               "customer_lookup",
               %{"customer_id" => "still-here"}
             )

    refute_received {:DOWN, ^source_monitor, :process, ^source, _reason}
  end

  test "runs a tenant MCP tool while an explicitly non-blocking conversation continues" do
    observer = self()
    result = {:ok, %{"content" => [%{"type" => "text", "text" => "Customer found."}]}}

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, result}], invocations: []} end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-live-call-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               mcp_catalog_store: RemoteMCPFixture.source!(integrations),
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, _key, opened_config}
    assert opened_config[:private] == "private-live-call-sentinel"

    {caller, connection_id} = attach_caller(plan, room)
    initial = send_text(plan, room, caller, connection_id, "Find the customer.")

    assert_receive {:test_agent_runtime_stream, provider, initial_request}
    assert Enum.map(initial_request.tools, & &1.name) == ["customer_lookup"]
    refute inspect(initial_request) =~ "private-live-call-sentinel"
    refute inspect(initial_request) =~ "lookup_customer"

    reply_with_tool(provider, "remote-live-call")

    assert_receive {:test_remote_mcp_invocation_started, execution}
    refute execution == provider
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "remote-live-call"}}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert_pending(acknowledgement, "remote-live-call")
    reply_with_text(acknowledgement_provider, "I am checking now.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}}
    assert initial_correlation == initial.correlation_id

    unrelated = send_text(plan, room, caller, connection_id, "What can we discuss meanwhile?")

    assert_receive {:test_agent_runtime_stream, unrelated_provider, unrelated_request}
    assert List.last(unrelated_request.messages).content == unrelated.content
    assert_pending(unrelated_request, "remote-live-call")
    reply_with_text(unrelated_provider, "We can discuss your account options.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: unrelated_correlation}}
    assert unrelated_correlation == unrelated.correlation_id

    send(execution, :release_test_remote_mcp)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "remote-live-call",
                      name: "customer_lookup",
                      result: %{"content" => [%{"type" => "text", "text" => "Customer found."}]}
                    }}

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "I found the customer.")
  end

  test "rejects a pinned remote generation replaced before room startup" do
    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(self(), self(), "private-stale-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store)
    assert {:ok, empty} = IntegrationCatalog.new(application: %{}, tenants: %{})
    assert :ok = CatalogStore.publish(store, empty)

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{
                "path" => ["participants", "reception", "tools", "customer_lookup"],
                "reason" => "pinned remote MCP generation is no longer available"
              }
            }} = CallEngine.start_call(plan, mcp_catalog_store: store)

    assert Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) == []
  end

  test "speaks the acknowledgement while a non-blocking remote invocation remains pending" do
    configure_text_to_speech()
    observer = self()
    remote_result = {:ok, %{"content" => [%{"type" => "text", "text" => "Customer found."}]}}

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, remote_result}], invocations: []} end}
      )

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-speaking-sentinel")

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store, speech: true)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})
    {caller, connection_id} = attach_caller(plan, room, sink)

    initial =
      send_text(plan, room, caller, connection_id, "Find the customer.", audio_response: true)

    assert_receive {:test_agent_runtime_stream, provider, _initial_request}
    reply_with_tool(provider, "remote-speaking")
    assert_receive {:test_remote_mcp_invocation_started, execution}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert_pending(acknowledgement, "remote-speaking")
    reply_with_text(acknowledgement_provider, "I am checking the customer.")

    complete_spoken_output(
      tts_transport,
      sink,
      "I am checking the customer.",
      "speech-acknowledgement"
    )

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}
    assert correlation_id == initial.correlation_id
    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "remote-speaking"}}, 50

    send(execution, :release_test_remote_mcp)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "remote-speaking"}}
    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "I found the customer.")

    complete_spoken_output(
      tts_transport,
      sink,
      "I found the customer.",
      "speech-completion"
    )
  end

  test "archives a scoped remote result before an authorized variables update" do
    observer = self()
    remote_result = %{"content" => [%{"type" => "text", "text" => "Customer found."}]}

    client =
      start_supervised!(
        {Agent,
         fn ->
           %{responses: [{:wait, observer, {:ok, remote_result}}], invocations: []}
         end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-history-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store, variables: true)

    archive = [
      enabled: true,
      writer: {Vxpipe.CallEngine.TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 64,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               archive: archive,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    {caller, connection_id} = attach_caller(plan, room)
    initial = send_text(plan, room, caller, connection_id, "Find and save the customer.")

    assert_receive {:test_agent_runtime_stream, remote_provider, remote_request}

    assert Enum.map(remote_request.tools, & &1.name) == [
             "customer_lookup",
             "read_variables",
             "update_variable",
             "update_variables"
           ]

    reply_with_tool(remote_provider, "remote-history")
    assert_receive {:test_remote_mcp_invocation_started, remote_execution}
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "remote-history"}}

    assert_receive {:test_agent_runtime_stream, remote_ack_provider, remote_ack_request}
    assert_pending(remote_ack_request, "remote-history")
    reply_with_text(remote_ack_provider, "I am checking the customer.")
    send(remote_execution, :release_test_remote_mcp)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "remote-history",
                      name: "customer_lookup",
                      result: ^remote_result
                    }}

    assert_receive {:test_agent_runtime_stream, variables_provider, variables_request}
    assert List.last(variables_request.messages).origin == :engine

    reply_with_tool(
      variables_provider,
      "save-customer",
      "update_variables",
      %{
        "section_name" => "customer",
        "data" => %{"customer_id" => "customer-42", "status" => "found"},
        "expected_revision" => 0
      }
    )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "save-customer",
                      name: "update_variables",
                      result: %{
                        "section" => "customer",
                        "revision" => 1,
                        "value" => %{
                          "customer_id" => "customer-42",
                          "status" => "found"
                        }
                      }
                    }}

    assert_receive {:test_agent_runtime_stream, variables_ack_provider, variables_ack_request}
    assert variables_ack_request.tools == []
    reply_with_text(variables_ack_provider, "I am saving the customer.")

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "The customer is saved.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}
    assert correlation_id == initial.correlation_id

    assert [remote_invocation] = Agent.get(client, & &1.invocations)
    assert remote_invocation.name == "lookup_customer"
    assert remote_invocation.arguments == %{"customer_id" => "customer-42"}
    assert Map.keys(remote_invocation) |> Enum.sort() == [:arguments, :name, :timeout]

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :tool_call_started,
                      tool_call_id: "remote-history",
                      payload: %{
                        "name" => "customer_lookup",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :tool_call_completed,
                      tool_call_id: "remote-history",
                      payload: %{"name" => "customer_lookup", "result" => ^remote_result}
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %UpdateSnapshot{
                      participant_id: participant_id,
                      tool_call_id: "save-customer",
                      section: "customer",
                      section_revision: 1,
                      sections: %{
                        "customer" => %{
                          revision: 1,
                          value: %{"customer_id" => "customer-42", "status" => "found"}
                        }
                      }
                    }},
                   2_000

    reception = Map.fetch!(plan.participants, "reception")
    assert participant_id == reception.participant_id
    refute inspect(remote_invocation) =~ "private-history-sentinel"
  end

  defp compile_plan(store, options \\ []) do
    assert {:ok, call_spec} =
             CallSpec.new(maybe_add_transfer(call_spec_input(options), options),
               resource_id: "remote-live",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "remote-live", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      host_tools: %{}
    }

    assert {:ok, plan} =
             CallEngine.compile_call_spec(call_spec, invocation, registries,
               mcp_catalog_store: store
             )

    plan
  end

  defp call_spec_input(options) do
    {call_variables, variable_permissions} = variables_call_spec(options)

    receiver_capabilities =
      %{model_inference: %{provider: "fixture", model: "test:scripted"}}
      |> maybe_enable_speech(options)

    %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{}},
      call_variables: call_variables,
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "reception" => %{
          type: "agent",
          prompt: "Use the available customer tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: receiver_capabilities,
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              tool: "lookup_customer",
              conversation_mode: "non_blocking"
            }
          },
          variable_permissions: variable_permissions,
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp maybe_add_transfer(input, options) do
    if Keyword.get(options, :transfer?, false) do
      reception = Map.fetch!(input.participants, "reception")

      participants =
        input.participants
        |> Map.put("reception", %{reception | transfers: ["records"]})
        |> Map.put("records", %{reception | transfers: ["reception"]})

      input
      |> Map.put(:participants, participants)
      |> Map.put(:transfer_policy, %{
        attempt_timeout_ms: Keyword.get(options, :transfer_timeout_ms, 1_000)
      })
      |> Map.put(:tool_visibility, "full")
    else
      input
    end
  end

  defp maybe_enable_speech(capabilities, options) do
    if Keyword.get(options, :speech, false) do
      Map.put(capabilities, :text_to_speech, %{
        provider: "deepgram",
        model: "flux-plan-voice",
        options: %{encoding: "linear16", sample_rate: 48_000}
      })
    else
      capabilities
    end
  end

  defp variables_call_spec(options) do
    if Keyword.get(options, :variables, false) do
      sections = %{
        "customer" => %{
          schema: %{
            "type" => "object",
            "properties" => %{
              "customer_id" => %{"type" => "string"},
              "status" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      }

      {%{sections: sections}, %{"customer" => ["read", "write"]}}
    else
      {%{sections: %{}}, %{}}
    end
  end

  defp attach_caller(plan, room, output_sink \\ nil) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    connection_id = unique_id("connection")

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, attachment} =
             Vxpipe.CallEngine.TestTransferConnection.attach(command, output_sink)

    Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)
    {:ok, attachment}
    {caller, connection_id}
  end

  defp send_text(plan, room, caller, connection_id, content, options \\ []) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               audio_response: Keyword.get(options, :audio_response, false),
               deadline: future_deadline()
             )

    assert :ok = Vxpipe.CallEngine.TestTransferConnection.send_text(command)
    command
  end

  defp reply_with_tool(provider, id) do
    reply_with_tool(provider, id, "customer_lookup", %{"customer_id" => "customer-42"})
  end

  defp wire_tool_turn(plan, room, {caller, connection_id}, id) do
    command = send_text(plan, room, caller, connection_id, "Find a customer.")
    command_id = command.id

    assert_receive {:test_agent_runtime_stream, provider,
                    %{correlation: %{command_id: ^command_id, invocation_registry: registry}}},
                   1_000

    reply_with_tool(provider, id)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 1_000

    assert_receive {:test_agent_runtime_stream, acknowledgement,
                    %{correlation: %{command_id: ^command_id}}},
                   1_000

    reply_with_text(acknowledgement, "Checking.")
    correlation = command.correlation_id
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^correlation}}, 1_000

    assert_receive {:test_agent_runtime_stream, completion,
                    %{
                      correlation: %{
                        invocation_registry: ^registry,
                        correlation_id: completion_id
                      }
                    }},
                   1_000

    reply_with_text(completion, "Found.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^completion_id}}, 1_000
  end

  defp active_mcp(plan, key, participant) do
    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    capability = :sys.get_state(authority).text_capability
    assert capability.participant_id == Map.fetch!(plan.participants, participant).participant_id

    host =
      Vxpipe.CallEngine.AgentActivationSupervisor.whereis_child(
        capability.activation_id,
        :remote_mcp_sessions
      )

    assert {:ok, connection} = Vxpipe.MCP.Connections.lookup(key, owner: host)
    {capability.activation_id, connection}
  end

  defp monitor_session_tree(supervisor) do
    children =
      Enum.flat_map(Supervisor.which_children(supervisor), fn
        {_id, pid, :supervisor, _modules} when is_pid(pid) -> monitor_session_tree(pid)
        {_id, pid, :worker, _modules} when is_pid(pid) -> [{pid, Process.monitor(pid)}]
      end)

    [{supervisor, Process.monitor(supervisor)} | children]
  end

  defp reply_with_tool(provider, id, name, arguments) do
    assert {:ok, call} =
             ToolCall.new(
               id: id,
               name: name,
               arguments: arguments
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp reply_with_text(provider, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_pending(request, invocation_id) do
    assert [
             %PendingInvocation{
               invocation_id: ^invocation_id,
               tool_name: "customer_lookup",
               conversation_mode: :non_blocking,
               status: :running
             }
           ] = request.pending_invocations

    assert Enum.count(request.messages, fn
             %Message{role: :tool, tool_call_id: ^invocation_id, content: content} ->
               JSON.decode!(content) == %{
                 "invocation_id" => invocation_id,
                 "status" => "running"
               }

             _message ->
               false
           end) == 1
  end

  defp complete_spoken_output(tts_transport, sink, expected_text, speech_id) do
    assert_receive {:test_tts_control, ^tts_transport, speak}, 2_000
    assert JSON.decode!(speak) == %{"text" => expected_text, "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, flush}, 2_000
    assert JSON.decode!(flush) == %{"type" => "Flush"}

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{"type" => "SpeechStarted", "request_id" => "req", "speech_id" => speech_id})
    )

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}, 2_000

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{"type" => "SpeechMetadata", "request_id" => "req", "speech_id" => speech_id})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn_id}, 2_000
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_started(sink)
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_completed(sink)
  end

  defp configure_text_to_speech do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      providers: %{
        Vxpipe.Providers.Deepgram.TTSSession => [
          enabled: true,
          wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
          wire_options: [observer: self(), ready_on_start: true],
          maximum_requests: 4
        ]
      }
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :text_to_speech, text_to_speech)
    )
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
