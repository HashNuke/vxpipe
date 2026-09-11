defmodule Vxpipe.CallEngine.HumanOnlyCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    Error,
    RoomMixer,
    TestCallLifecycleTimer
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  test "starts two human entries without an agent, mixes audio, and retains call lifecycle" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert caller.kind == :human
    assert receiver.kind == :human
    assert receiver.activation_id == nil

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
    _ = registered_participant(plan, caller.participant_id)
    _ = registered_participant(plan, receiver.participant_id)

    attach(plan, room, caller, "conn-human-caller")
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    attach(plan, room, receiver, "conn-human-receiver")

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    state = :sys.get_state(authority)
    assert state.text_capability == nil
    assert state.text_capability_required? == false

    mixer = RoomMixer.whereis(room.incarnation_id)
    assert %{policy_revision: 2} = RoomMixer.stats(mixer)

    caller_output = subscribe(mixer, plan, room, caller.participant_id, "caller-output")
    receiver_output = subscribe(mixer, plan, room, receiver.participant_id, "receiver-output")

    caller_audio = :binary.copy(<<100::little-signed-16>>, 960)
    receiver_audio = :binary.copy(<<200::little-signed-16>>, 960)

    assert :ok =
             RoomMixer.push(
               mixer,
               normalized_frame(plan, room, caller.participant_id, caller_audio)
             )

    assert :ok =
             RoomMixer.push(
               mixer,
               normalized_frame(plan, room, receiver.participant_id, receiver_audio)
             )

    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 0)
    assert_mix(Subscription.take(caller_output, 1), receiver.participant_id, receiver_audio)
    assert_mix(Subscription.take(receiver_output, 1), caller.participant_id, caller_audio)

    command = send_command(plan, room, caller, "conn-human-caller")
    assert {:error, %Error{code: :agent_not_ready}} = CallEngine.send_text(command)

    room_monitor = Process.monitor(authority)
    :ok = TestCallLifecycleTimer.fire(maximum_timer)

    assert_receive {:DOWN, ^room_monitor, :process, ^authority,
                    {:shutdown, :maximum_duration_reached}}
  end

  defp compile_plan do
    room_id = unique_id("room-human-only")

    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant()
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "human-only", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "human-only", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-only",
               actor_id: "actor-human-only",
               call_id: unique_id("call-human-only"),
               room_id: room_id
             )

    registries = %{capability_profiles: %{}, host_tools: %{}}
    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp human_participant do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }
  end

  defp attach(plan, room, participant, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(command)
  end

  defp subscribe(mixer, plan, room, participant_id, id) do
    assert {:ok, subscription} =
             RoomMixer.subscribe(mixer,
               id: id,
               tenant_id: plan.tenant_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               recipient_participant_id: participant_id,
               mode: :mix_minus,
               subscriber: self()
             )

    subscription
  end

  defp normalized_frame(plan, room, source_participant_id, payload) do
    %NormalizedFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      source_participant_id: source_participant_id,
      track_id: "track-#{source_participant_id}",
      sequence_number: 1,
      timestamp: 0,
      policy_revision: 2,
      sample_rate: 48_000,
      channels: 1,
      payload: payload
    }
  end

  defp send_command(plan, room, caller, connection_id) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn-human-only"),
               content: "Is an agent here?",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp registered_participant(plan, participant_id) do
    [{pid, _value}] =
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {:participant, plan.tenant_id, plan.room_id, participant_id}
      )

    _ = :sys.get_state(pid)
    pid
  end

  defp assert_mix(
         {:ok, [%MixedFrame{source_participant_ids: [source_id], payload: payload}]},
         expected_source_id,
         expected_payload
       ) do
    assert source_id == expected_source_id
    assert payload == expected_payload
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
