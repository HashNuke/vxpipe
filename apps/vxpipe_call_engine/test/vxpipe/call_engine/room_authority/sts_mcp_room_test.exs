defmodule Vxpipe.CallEngine.RoomAuthority.STSMCPRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, RemoteMCPFixture, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallStarted}
  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationCatalog}
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.STSSession
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession

  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_speech,
        providers: %{STSSession => [enabled: true], DuplexSTSSession => [enabled: true]}
      )
      |> Keyword.update!(:agent_runtime, fn settings ->
        Keyword.put(
          settings,
          :fixture,
          {CallEngine.TestSelectiveAgentRuntimeModelProvider, [owner: self()]}
        )
      end)

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    :ok
  end

  test "a native participant invokes its selected MCP alias and retires the owned session" do
    context = scene() |> start_room()
    %{client: client, plan: plan, room: room, capability: capability, result: result} = context
    assert_receive {:test_remote_mcp_open_options, key, options}, 1_000
    host = Keyword.fetch!(options, :owner)

    tree = Tree.parent(capability)

    assert Enum.any?(Supervisor.which_children(tree), fn {_id, pid, _type, _modules} ->
             pid == host
           end)

    assert {:ok, connection} = Vxpipe.MCP.Connections.lookup(key, owner: host)
    session = Vxpipe.MCP.Connection.client(connection)
    monitor = Process.monitor(session)

    assert :ok =
             SpeechToSpeech.push_text(capability, ~s(TOOL customer_lookup {"customer_id":"42"}))

    assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"} = started}, 1_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{name: "customer_lookup", result: ^result} = completed},
                   1_000

    assert completed.tool_call_id == started.tool_call_id

    assert [%{name: "lookup_customer", arguments: %{"customer_id" => "42"}}] =
             Agent.get(client, & &1.invocations)

    assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^monitor, :process, ^session, _reason}, 1_000
  end

  @tag :mcp_readiness
  test "MCP readiness waits outside capability control and keeps caller input closed" do
    context = scene(test_gate_initialization: true) |> start_room(false)
    assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
    owner = Tree.remote_mcp_owner(context.capability)
    :erlang.trace(owner, true, [:receive])
    tasks = start_supervised!({Task.Supervisor, name: {:global, {__MODULE__, make_ref()}}})

    probe =
      Task.Supervisor.async_nolink(tasks, fn -> SpeechToSpeech.readiness(context.capability) end)

    assert_receive {:trace, ^owner, :receive, {:"$gen_call", _from, :readiness}}, 1_000
    assert Task.yield(probe, 0) == nil
    assert {:ok, _format} = GenServer.call(context.capability, :input_format, 250)
    assert %CallEngine.Room.Snapshot{} = GenServer.call(context.authority, :snapshot, 250)
    state = :sys.get_state(context.authority)
    refute state.speech_to_speech_ready?
    assert state.speech_to_speech_capability.input_epoch == nil
    refute_received {:test_call_ready, _}
    assert Agent.get(context.client, & &1.invocations) == []

    send(initializer, :test_remote_mcp_initialized)
    assert {:ok, _resource, :ready} = Task.await(probe, 2_000)
    TestCallStartup.await_ready(context.plan.room_id)
    assert is_reference(:sys.get_state(context.authority).speech_to_speech_capability.input_epoch)
  end

  @tag :mcp_readiness
  test "ending a call while MCP initializes removes its initializer and owned subtree" do
    context = scene(test_gate_initialization: true) |> start_room(false)
    assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
    owner = Tree.remote_mcp_owner(context.capability)
    host = Tree.remote_mcp_sessions(context.capability)

    monitors =
      Enum.map([initializer, owner, host, context.capability], &{&1, Process.monitor(&1)})

    assert :ok =
             CallEngine.end_call(
               context.plan.tenant_id,
               context.plan.room_id,
               context.room.incarnation_id
             )

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end

    refute_received {:test_call_ready, _}
    assert Agent.get(context.client, & &1.invocations) == []
  end

  test "simultaneous native calls pin distinct owners and ending one preserves the other" do
    scene = scene()
    first = start_room(scene)
    second = start_room(%{scene | plan: compile_plan(scene.store)})
    first_owner = Tree.remote_mcp_owner(first.capability)
    second_owner = Tree.remote_mcp_owner(second.capability)
    first_host = Tree.remote_mcp_sessions(first.capability)
    second_host = Tree.remote_mcp_sessions(second.capability)
    refute first_owner == second_owner
    refute first_host == second_host

    assert_receive {:test_remote_mcp_open_options, key, _}, 1_000
    assert_receive {:test_remote_mcp_open_options, ^key, _}, 1_000
    assert {:ok, first_connection} = Vxpipe.MCP.Connections.lookup(key, owner: first_host)
    assert {:ok, second_connection} = Vxpipe.MCP.Connections.lookup(key, owner: second_host)
    first_client = Vxpipe.MCP.Connection.client(first_connection)
    refute first_client == Vxpipe.MCP.Connection.client(second_connection)

    for {context, owner} <- [{first, first_owner}, {second, second_owner}] do
      runtime = :sys.get_state(context.authority).speech_to_speech_runtime

      assert {:ok, descriptor} =
               Vxpipe.AgentRuntime.ToolRegistry.resolve(
                 runtime.tool_registry,
                 "customer_lookup",
                 %{"customer_id" => "42"}
               )

      assert descriptor.binding.handler == {:remote_mcp, owner}
    end

    monitor = Process.monitor(first_client)

    assert :ok =
             CallEngine.end_call(
               first.plan.tenant_id,
               first.plan.room_id,
               first.room.incarnation_id
             )

    assert_receive {:DOWN, ^monitor, :process, ^first_client, _reason}, 1_000

    assert {:error, :tool_failed} =
             CallEngine.RemoteMCP.IntegrationOwner.execute(first_owner, "customer_lookup", %{
               "customer_id" => "old"
             })

    assert Agent.get(scene.client, & &1.invocations) == []

    assert :ok =
             SpeechToSpeech.push_text(
               second.capability,
               ~s(TOOL customer_lookup {"customer_id":"second"})
             )

    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "customer_lookup"}}, 1_000

    assert [%{arguments: %{"customer_id" => "second"}}] =
             Agent.get(scene.client, & &1.invocations)
  end

  test "tools-first readiness waits for the provider and ignores stale owner notifications" do
    context = scene(test_gate_initialization: true) |> start_room(false)
    assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
    owner = Tree.remote_mcp_owner(context.capability)

    # Consume the fixture's original ready signal before replaying the opposite
    # ordering; otherwise that queued signal can race the deliberate delay.
    authority = context.authority
    capability = context.capability
    :erlang.trace(authority, true, [:receive])

    unless :sys.get_state(authority).speech_to_speech_capability.provider_ready? do
      assert_receive {:trace, ^authority, :receive, {:vxpipe_sts_ready, ^capability}}, 1_000
    end

    # Delay the provider notification independently of MCP completion.
    :sys.replace_state(context.authority, fn state ->
      put_in(state.speech_to_speech_capability.provider_ready?, false)
    end)

    state = :sys.get_state(context.authority)
    activation = state.speech_to_speech_runtime.activation_id
    send(context.authority, {:vxpipe_remote_tools_ready, self(), activation})
    send(context.authority, {:vxpipe_remote_tools_ready, owner, "retired-activation"})
    refute :sys.get_state(context.authority).speech_to_speech_capability.tools_ready?

    send(initializer, :test_remote_mcp_initialized)

    assert_receive {:trace, ^authority, :receive,
                    {:vxpipe_remote_tools_ready, ^owner, ^activation}},
                   1_000

    state = :sys.get_state(authority)
    assert state.speech_to_speech_capability.tools_ready?
    refute state.speech_to_speech_ready?
    assert state.speech_to_speech_capability.input_epoch == nil

    send(authority, {:vxpipe_sts_ready, context.capability})
    TestCallStartup.await_ready(context.plan.room_id)
    state = :sys.get_state(authority)
    ingress = state.speech_to_speech_capability.ingress
    send(authority, {:vxpipe_sts_ready, context.capability})
    send(authority, {:vxpipe_remote_tools_ready, owner, activation})
    assert :sys.get_state(authority).speech_to_speech_capability.ingress == ingress
  end

  test "MCP owner loss during recovery terminates the room and its unfinished initialization" do
    context = scene(test_gate_initialization: true) |> start_room(false)
    assert_receive {:test_remote_mcp_initializing, initializer}, 1_000
    send(initializer, :test_remote_mcp_initialized)
    TestCallStartup.await_ready(context.plan.room_id)
    old_owner = Tree.remote_mcp_owner(context.capability)
    old_monitor = Process.monitor(old_owner)

    state =
      :sys.replace_state(context.authority, fn state ->
        connection =
          Map.fetch!(state.connections, state.speech_to_speech_capability.connection_id)

        state
        |> CallEngine.RoomAuthority.SpeechToSpeech.stop()
        |> CallEngine.RoomAuthority.SpeechToSpeech.maybe_start(connection)
      end)

    assert_receive {:DOWN, ^old_monitor, :process, ^old_owner, _}, 1_000
    assert_receive {:test_remote_mcp_initializing, recovering}, 1_000
    replacement = state.speech_to_speech_capability.pid
    owner = Tree.remote_mcp_owner(replacement)
    refute owner == old_owner
    assert is_reference(state.speech_to_speech_capability.mcp_timer)
    refute :sys.get_state(context.authority).speech_to_speech_ready?

    for pid <- [context.authority, recovering, replacement], do: Process.monitor(pid)
    Process.exit(owner, :kill)

    for pid <- [context.authority, recovering, replacement] do
      assert_receive {:DOWN, _monitor, :process, ^pid, _reason}, 1_000
    end
  end

  test "a stale native catalog pin fails before allocating any connection" do
    scene = scene()
    assert {:ok, empty} = IntegrationCatalog.new(application: %{}, tenants: %{})
    assert :ok = CatalogStore.publish(scene.store, empty)

    assert {:error, %CallEngine.Error{code: :unsupported_call_plan}} =
             CallEngine.start_call(scene.plan, mcp_catalog_store: scene.store)

    refute_received {:test_remote_mcp_opened, _, _}
  end

  test "credential revocation fences in-flight native MCP work and removes its session subtree" do
    context = scene() |> start_room()
    observer = self()
    Agent.update(context.client, &%{&1 | responses: [{:wait, observer, {:ok, context.result}}]})
    assert_receive {:test_remote_mcp_open_options, key, _}, 1_000
    owner = Tree.remote_mcp_owner(context.capability)
    host = Tree.remote_mcp_sessions(context.capability)

    assert :ok =
             SpeechToSpeech.push_text(
               context.capability,
               ~s(TOOL customer_lookup {"customer_id":"42"})
             )

    assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
    pids = [owner, host, context.capability, worker]
    for pid <- pids, do: Process.monitor(pid)
    assert :ok = Vxpipe.MCP.Connections.revoke(key)

    for pid <- pids do
      assert_receive {:DOWN, _monitor, :process, ^pid, _reason}, 1_000
    end

    assert {:error, :tool_failed} =
             CallEngine.RemoteMCP.IntegrationOwner.execute(owner, "customer_lookup", %{
               "customer_id" => "late"
             })

    refute_received {:vxpipe_event, %ToolCallCompleted{name: "customer_lookup"}}
    assert length(Agent.get(context.client, & &1.invocations)) == 1
  end

  for loss <- [:call, :owner] do
    test "#{loss} loss ends all owned in-flight native MCP resources" do
      context = scene() |> start_room()
      observer = self()
      Agent.update(context.client, &%{&1 | responses: [{:wait, observer, {:ok, context.result}}]})
      assert_receive {:test_remote_mcp_open_options, key, _}, 1_000
      owner = Tree.remote_mcp_owner(context.capability)
      host = Tree.remote_mcp_sessions(context.capability)
      assert {:ok, connection} = Vxpipe.MCP.Connections.lookup(key, owner: host)
      client = Vxpipe.MCP.Connection.client(connection)

      assert :ok =
               SpeechToSpeech.push_text(
                 context.capability,
                 ~s(TOOL customer_lookup {"customer_id":"42"})
               )

      assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000

      monitors =
        Enum.map([owner, host, client, context.capability, worker], &{&1, Process.monitor(&1)})

      case unquote(loss) do
        :call ->
          assert :ok =
                   CallEngine.end_call(
                     context.plan.tenant_id,
                     context.plan.room_id,
                     context.room.incarnation_id
                   )

        :owner ->
          Process.exit(owner, :kill)
      end

      for {pid, monitor} <- monitors do
        assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
      end

      assert {:error, :tool_failed} =
               CallEngine.RemoteMCP.IntegrationOwner.execute(owner, "customer_lookup", %{
                 "customer_id" => "late"
               })

      assert length(Agent.get(context.client, & &1.invocations)) == 1
      refute_received {:vxpipe_event, %ToolCallCompleted{name: "customer_lookup"}}
    end
  end

  test "tenant catalogs and call sessions stay separate while snapshots are refreshed" do
    first = scene(tenant: "tenant-one") |> start_room()
    second = scene(tenant: "tenant-two") |> start_room()
    assert_receive {:test_remote_mcp_open_options, first_key, _}, 1_000
    assert_receive {:test_remote_mcp_open_options, second_key, _}, 1_000
    assert first_key.scope == {:tenant, "tenant-one"}
    assert second_key.scope == {:tenant, "tenant-two"}
    assert {:ok, empty} = IntegrationCatalog.new(application: %{}, tenants: %{})
    assert :ok = CatalogStore.publish(first.store, empty)

    assert :ok =
             CallEngine.end_call(
               first.plan.tenant_id,
               first.plan.room_id,
               first.room.incarnation_id
             )

    assert {:ok, ^empty} = CatalogStore.snapshot(first.store)

    assert :ok =
             SpeechToSpeech.push_text(
               second.capability,
               ~s(TOOL customer_lookup {"customer_id":"second-tenant"})
             )

    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "customer_lookup"}}, 1_000
    assert Agent.get(first.client, & &1.invocations) == []

    assert [%{arguments: %{"customer_id" => "second-tenant"}}] =
             Agent.get(second.client, & &1.invocations)
  end

  for outcome <- [:success, :failure], native_model <- ["morse", "morse-duplex"] do
    @tag :interruption_delivery
    test "#{native_model} MCP ownership survives preparation and follows transfer #{outcome}" do
      model =
        if unquote(outcome) == :success, do: "test:blocked", else: "test:blocked-unavailable"

      context = scene(destination: model, native_model: unquote(native_model)) |> start_room()
      owner = Tree.remote_mcp_owner(context.capability)
      host = Tree.remote_mcp_sessions(context.capability)
      owner_monitor = Process.monitor(owner)
      assert_receive {:test_remote_mcp_open_options, key, _}, 1_000

      assert :ok =
               SpeechToSpeech.push_text(
                 context.capability,
                 ~s(TOOL transfer {"destination":"billing"})
               )

      assert_receive {:test_agent_runtime_model_preparing, preparer}, 1_000
      assert {:ok, _resource, :ready} = CallEngine.RemoteMCP.IntegrationOwner.readiness(owner)
      refute_received {:DOWN, ^owner_monitor, :process, ^owner, _}
      send(preparer, :release_test_agent_runtime_model)

      if unquote(outcome) == :success do
        assert_receive {:test_remote_mcp_open_options, ^key, options}, 1_000
        destination_host = Keyword.fetch!(options, :owner)
        refute destination_host == host
        assert_receive {:vxpipe_event, %ToolCallCompleted{name: "transfer"}}, 2_000
        assert_receive {:DOWN, ^owner_monitor, :process, ^owner, _}, 1_000
        assert {:ok, _connection} = Vxpipe.MCP.Connections.lookup(key, owner: destination_host)
      else
        assert_receive {:vxpipe_event, %CallEngine.Event.ToolCallFailed{name: "transfer"}}, 2_000
        assert Tree.remote_mcp_owner(context.capability) == owner
        _ = :sys.get_state(context.authority)

        assert :ok =
                 SpeechToSpeech.push_text(
                   context.capability,
                   ~s(TOOL customer_lookup {"customer_id":"after-failed-transfer"})
                 )

        assert_receive {:vxpipe_event, %ToolCallCompleted{name: "customer_lookup"}}, 1_000
        refute_received {:DOWN, ^owner_monitor, :process, ^owner, _}
      end
    end
  end

  defp scene(options \\ []) do
    {tenant, options} = Keyword.pop(options, :tenant, "tenant-demo")
    {destination, options} = Keyword.pop(options, :destination)
    {native_model, options} = Keyword.pop(options, :native_model, "morse")
    result = %{"content" => [%{"type" => "text", "text" => "appointment found"}]}

    client =
      start_supervised!({Agent, fn -> %{responses: [{:ok, result}], invocations: []} end},
        id: make_ref()
      )

    config = [test_client: client, test_observer: self()] ++ options

    {catalog, binding} =
      RemoteMCPFixture.binding!(client, self(), "synthetic-private",
        client_config: config,
        credential_generation: "credential-#{System.unique_integer([:positive])}"
      )

    assert {:ok, integration} = IntegrationCatalog.checkout(catalog, binding.remote)

    assert {:ok, catalog} =
             IntegrationCatalog.new(
               application: %{},
               tenants: %{tenant => %{"records" => integration}}
             )

    store = RemoteMCPFixture.source!(catalog)

    %{
      client: client,
      store: store,
      plan: compile_plan(store, tenant, destination, native_model),
      result: result
    }
  end

  defp start_room(%{plan: plan, store: store} = scene, ready? \\ true) do
    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: CallEngine.TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: CallEngine.TestRemoteMCPProtocolClient
             )

    on_exit(fn -> CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id) end)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} = TestTransferConnection.attach(command, sink, input_track: @track)
    if ready?, do: TestCallStartup.await_ready(plan.room_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    Map.merge(scene, %{room: room, capability: capability, authority: authority})
  end

  defp compile_plan(store, tenant \\ "tenant-demo", destination \\ nil, native_model \\ "morse") do
    source = %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Look up the appointment.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{speech_to_speech: %{provider: "morse", model: native_model}},
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              tool: "lookup_customer",
              conversation_mode: "blocking"
            }
          },
          transfers: []
        }
      }
    }

    source =
      if destination do
        billing = %{
          type: "agent",
          prompt: "Handle billing.",
          tools: source.participants["assistant"].tools,
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: destination}}
        }

        source
        |> put_in([:participants, "assistant", :transfers], ["billing"])
        |> put_in([:participants, "billing"], billing)
      else
        source
      end

    assert {:ok, spec} = CallSpec.new(source, resource_id: "native-mcp", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "native-mcp", revision: 1}, transport: %{type: "web"}},
               tenant_id: tenant,
               actor_id: "actor"
             )

    assert {:ok, plan} =
             CallEngine.compile_call_spec(spec, invocation, %{host_tools: %{}},
               mcp_catalog_store: store
             )

    plan
  end
end
