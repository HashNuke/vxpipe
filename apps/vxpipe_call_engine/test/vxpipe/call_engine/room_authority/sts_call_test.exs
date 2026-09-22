defmodule Vxpipe.CallEngine.RoomAuthority.STSCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestCallStartup, TestTransferConnection}
  alias Vxpipe.Providers.MorseCode.STSSession

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_speech, providers: %{STSSession => [enabled: true]})
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "a real STS room becomes ready and retires the allocation when its source disconnects" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    agent = Map.fetch!(plan.participants, plan.entry_receiver)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "sts-connection-#{System.unique_integer([:positive])}",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    room_id = plan.room_id

    receive do
      {:test_call_ready, ^room_id} -> :ok
    after
      2_000 ->
        [{authority, _}] =
          Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

        state = :sys.get_state(authority)

        flunk(
          "STS readiness failed: #{inspect(Map.take(state, [:startup, :speech_to_speech_ready?]))}"
        )
    end

    capability =
      RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent.participant_id)

    assert is_pid(capability)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, room_id})

    policy_authority = Vxpipe.CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)
    policy = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(policy_authority)

    assert {:ok, candidate} =
             Vxpipe.CallEngine.MediaPolicy.Authority.preview_presence(
               policy_authority,
               policy.present_participant_ids
             )

    assert {:ok, graph} = Vxpipe.CallEngine.Readiness.Preparation.run(authority, candidate)

    assert Enum.any?(graph.resources, fn resource ->
             resource.kind == :speech_to_speech and resource.instance == capability and
               resource.scope == {:participant, agent.participant_id}
           end)

    tree = Tree.parent(capability)
    assert is_pid(tree)
    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)

    duplicate = %{command | connection_id: command.connection_id <> "-duplicate"}

    assert {:error, %Vxpipe.CallEngine.Error{code: :sts_source_already_attached}} =
             TestTransferConnection.attach(duplicate, sink)

    stop_supervised!({TestTransferConnection, command.connection_id})
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 1_000
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}, 1_000
  end

  test "rejected policy registration retires the candidate instead of binding it" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    assert {:ok, room} = TestCallStartup.start_call(plan)

    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)
    snapshot = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(state.media_policy_authority)

    rejecting =
      start_supervised!(
        {Vxpipe.CallEngine.TestSTSRejectingPolicyAuthority, snapshot: snapshot, observer: self()}
      )

    state = %{state | media_policy_authority: rejecting}

    connection = %{
      output_sink: sink,
      pid: self(),
      participant_id: caller.participant_id,
      attach_command: %{connection_id: "rejected-source"}
    }

    result = Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.maybe_start(state, connection)
    assert result.speech_to_speech_capability == nil
    assert_receive {:sts_policy_registration_rejected, capability, tree}
    capability_monitor = Process.monitor(capability)
    tree_monitor = Process.monitor(tree)
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}
    assert_receive {:DOWN, ^tree_monitor, :process, ^tree, _}

    assert RoomCapabilitySupervisor.whereis_speech_to_speech(
             room.incarnation_id,
             state.speech_to_speech_runtime.participant_id
           ) == nil
  end

  defp compile_plan do
    source = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Reply using Morse speech.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          capabilities: %{speech_to_speech: %{provider: "morse", model: "morse", options: %{}}}
        }
      }
    }

    assert {:ok, spec} = CallSpec.new(source, resource_id: "sts-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "sts-room", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-sts-room",
               actor_id: "actor-sts-room"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
