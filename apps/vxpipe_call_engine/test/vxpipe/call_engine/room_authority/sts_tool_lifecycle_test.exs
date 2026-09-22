defmodule Vxpipe.CallEngine.RoomAuthority.STSToolLifecycleTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Tool.InvocationRegistry
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.STSSession

  @track %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    settings =
      Keyword.put(original, :speech_to_speech, providers: %{STSSession => [enabled: true]})

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    room()
  end

  test "actual room host work is invocation-owned and its result stays leased", context do
    {worker, started} = submit(context)
    registry = Tree.invocation_registry(context.capability)
    supervisor = Tree.invocation_supervisor(context.capability)
    assert [{_, invocation, :worker, _}] = DynamicSupervisor.which_children(supervisor)
    assert {:links, links} = Process.info(worker, :links)
    assert invocation in links
    assert {:ok, [status]} = InvocationRegistry.snapshot(registry)
    assert status.invocation_id == started.tool_call_id
    assert status.status == :running
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    assert_receive {:vxpipe_event, %ToolCallCompleted{} = completed}, 1_000
    assert completed.tool_call_id == started.tool_call_id
    assert completed.correlation_id == started.correlation_id
    assert {:ok, [status]} = InvocationRegistry.snapshot(registry)
    assert status.status == :completion_admitted
    [lease] = leases(context)
    assert lease.completion.outcome == {:ok, %{"retained" => true}}
    assert lease.completion.context.tool_call_id == started.tool_call_id
  end

  test "ordinary provider association interruption preserves accepted work and private outcome",
       context do
    {worker, started} = submit(context)
    bridge = Tree.tool_completions(context.capability)
    :erlang.trace(bridge, true, [:send])
    assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
    assert_receive {:vxpipe_event, %ToolCallCancelled{tool_call_id: id}}, 1_000
    assert id == started.tool_call_id
    send(worker, :probe)
    assert_receive {:host_running, ^worker}
    send(worker, :finish)
    assert_receive {:trace, ^bridge, :send, {:vxpipe_sts_tool_completion, ^bridge, _}, _}, 1_000
    _ = :sys.get_state(context.authority)
    [lease] = leases(context)
    assert lease.invocation_id == started.tool_call_id
    assert lease.completion.outcome == {:ok, %{"retained" => true}}
    refute_received {:vxpipe_event, %ToolCallCompleted{}}
    assert :sys.get_state(context.capability).tool_calls == %{}
  end

  test "five-second execution deadline kills the host worker and retains UNKNOWN", context do
    {worker, _} = submit(context)
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 6_000
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unknown}}, 1_000
    [lease] = leases(context)
    assert lease.completion.outcome == {:error, :unknown}
  end

  for loss <- [:capability, :activation, :room_owner, :registry, :supervisor, :bridge] do
    test "#{loss} loss ends actual submitted host work", context do
      {worker, _} = submit(context)
      monitor = Process.monitor(worker)

      case unquote(loss) do
        :capability ->
          Process.exit(context.capability, :kill)

        :activation ->
          assert :ok =
                   RoomCapabilitySupervisor.stop_capability(
                     context.room.incarnation_id,
                     context.capability
                   )

        :room_owner ->
          Process.exit(context.authority, :kill)

        :registry ->
          Process.exit(Tree.invocation_registry(context.capability), :kill)

        :supervisor ->
          Process.exit(Tree.invocation_supervisor(context.capability), :kill)

        :bridge ->
          Process.exit(Tree.tool_completions(context.capability), :kill)
      end

      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    end
  end

  test "interrupted running work remains bounded even when all provider associations retire",
       context do
    workers =
      for _ <- 1..16 do
        {worker, _} = submit(context)
        assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
        assert_receive {:vxpipe_event, %ToolCallCancelled{}}, 1_000
        worker
      end

    assert DynamicSupervisor.count_children(Tree.invocation_supervisor(context.capability)).active ==
             16

    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :saturated}}, 1_000
    refute_received {:host_started, _, _}

    for worker <- workers do
      monitor = Process.monitor(worker)
      send(worker, :finish)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    end
  end

  test "retired provider calls do not free the 16-invocation execution budget", context do
    bridge = Tree.tool_completions(context.capability)
    assert is_pid(bridge)
    :erlang.trace(bridge, true, [:send])

    for _ <- 1..16 do
      {worker, _} = submit(context)
      assert {:ok, 0} = SpeechToSpeech.interrupt(context.capability)
      assert_receive {:vxpipe_event, %ToolCallCancelled{}}, 1_000
      send(worker, :finish)
      assert_receive {:trace, ^bridge, :send, {:vxpipe_sts_tool_completion, ^bridge, _}, _}, 1_000
      _ = :sys.get_state(context.authority)
    end

    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")
    assert_receive {:vxpipe_event, %ToolCallFailed{reason: :saturated}}, 1_000
    refute_received {:host_started, _, _}
    assert length(leases(context)) == 16

    assert DynamicSupervisor.count_children(Tree.invocation_supervisor(context.capability)).active ==
             0
  end

  defp leases(context) do
    GenServer.call(Tree.tool_completions(context.capability), :leases)
  end

  test "expired room admission cannot execute after a blocked supervisor resumes", context do
    registry = Tree.invocation_registry(context.capability)
    supervisor = Tree.invocation_supervisor(context.capability)
    :erlang.trace(registry, true, [:send])
    :ok = :sys.suspend(supervisor)

    try do
      assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")

      assert_receive {:trace, ^registry, :send, {:"$gen_call", _, {:start_child, _}},
                      ^supervisor},
                     1_000

      assert_receive {:vxpipe_event, %ToolCallFailed{reason: :unavailable}}, 3_000
    after
      :sys.resume(supervisor)
      :erlang.trace(registry, false, [:send])
    end

    assert {:ok, []} = InvocationRegistry.snapshot(registry)
    assert DynamicSupervisor.which_children(supervisor) == []
    refute_receive {:host_started, _, _}
  end

  defp submit(context) do
    assert :ok = SpeechToSpeech.push_text(context.capability, "TOOL lifecycle {}")
    assert_receive {:vxpipe_event, %ToolCallStarted{} = started}, 1_000
    assert_receive {:host_started, worker, tool_context}, 1_000
    assert tool_context.tool_call_id == started.tool_call_id
    assert tool_context.correlation_id == started.correlation_id
    {worker, started}
  end

  defp room do
    speech = %{provider: "morse", model: "morse", options: %{unit_duration_ms: 20}}

    source = %{
      schema_version: CallSpec.schema_version(),
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
          prompt: "Test tools.",
          tools: %{"lifecycle" => %{type: "host", tool: "lifecycle"}},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: %{speech_to_speech: speech}
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-lifecycle", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-lifecycle", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-lifecycle",
               actor_id: "actor"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(spec, invocation, %{
               host_tools: %{"lifecycle" => CallEngine.STSLifecycleTool}
             })

    {:ok, _} =
      Registry.register(CallEngine.RoomRegistry, {CallEngine.STSLifecycleTool, plan.room_id}, nil)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "source",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} = TestTransferConnection.attach(command, sink, input_track: @track)
    TestCallStartup.await_ready(plan.room_id)

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    %{authority: authority, capability: capability, room: room}
  end
end
