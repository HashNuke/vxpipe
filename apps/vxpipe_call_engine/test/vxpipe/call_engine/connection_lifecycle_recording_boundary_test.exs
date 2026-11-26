defmodule Vxpipe.CallEngine.ConnectionLifecycleRecordingBoundaryTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.TestRecordingBindingMixer
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, FirstMessage, OpeningAudio, State}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime

  setup do
    tenant = "tenant-rec-bound"
    room = "room-rec-bound"
    incarnation = "incarnation-rec-bound"

    counters = EgressHandoff.new_counters()
    :ok = EgressHandoff.install_policy(counters, 0, true)
    clock_origin = System.monotonic_time(:millisecond)

    identity = %{tenant_id: tenant, room_id: room, incarnation_id: incarnation}

    config = %{
      channels: 1,
      clock: fn -> System.monotonic_time(:millisecond) end,
      clock_origin_ms: clock_origin,
      frame_samples: 480,
      gate: counters,
      sample_rate: 48_000
    }

    mixer = start_supervised!({TestRecordingBindingMixer, {self(), identity, config, counters}})

    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})

    %{
      tenant: tenant,
      room: room,
      incarnation: incarnation,
      mixer: mixer,
      sink: sink,
      counters: counters,
      identity: identity,
      config: config
    }
  end

  defp plan_with(call_record, entries, context) do
    participants =
      Map.new(entries, fn {key, {participant_id, while_record}} ->
        {
          key,
          %ResolvedCallPlan.Participant{
            call_spec_key: key,
            participant_id: participant_id,
            activation_id: nil,
            kind: :human,
            description: nil,
            connection: nil,
            transfer_notice: nil,
            prompt: nil,
            first_message: nil,
            first_message_text: nil,
            capabilities: %ResolvedCallPlan.Capabilities{},
            while_present: %ResolvedCallPlan.MediaPolicy{
              audio_routes: :inherit,
              transcript_routes: :inherit,
              record_audio: while_record,
              save_transcripts: :inherit
            },
            tools: %{},
            transfers: [],
            transfer_history: nil,
            variable_permissions: %{}
          }
        }
      end)

    entry_key =
      if Map.has_key?(participants, "caller"),
        do: "caller",
        else: participants |> Map.keys() |> List.first()

    %ResolvedCallPlan{
      call_spec_id: "spec-rec-bound",
      call_spec_revision: 1,
      schema_version: "1",
      tenant_id: context.tenant,
      actor_id: "actor-rec-bound",
      call_id: "call-rec-bound",
      room_id: context.room,
      transport: :web,
      entry_caller: entry_key,
      entry_receiver: entry_key,
      opening_audio: nil,
      media_policy: %ResolvedCallPlan.MediaPolicy{
        audio_routes: :inherit,
        transcript_routes: :inherit,
        record_audio: call_record,
        save_transcripts: :inherit
      },
      participants: participants,
      transfer_policy: %Vxpipe.CallEngine.CallSpec.TransferPolicy{attempt_timeout_ms: 30_000},
      call_variables: %{},
      tool_visibility: %{},
      max_duration_ms: 60_000
    }
  end

  defp base_state(context, plan, participant_ids, roles) do
    snapshot = %Snapshot{
      tenant_id: context.tenant,
      room_id: context.room,
      incarnation_id: context.incarnation,
      lifecycle: :open,
      created_by_actor_id: "actor-rec-bound",
      created_by_command_id: "cmd-room"
    }

    %State{
      archive_recorder: %Recorder{port: nil, participant_activations: %{}},
      call_lifecycle: nil,
      first_message: FirstMessage.completed(),
      media_policy_authority: nil,
      opening_audio: OpeningAudio.open(),
      room_mixer: context.mixer,
      transcript_router: nil,
      snapshot: snapshot,
      speech_to_text_runtime: %{},
      startup_ready?: true,
      text_capability_required?: false,
      participant_transfer_runtime: %Runtime{plan: plan, startup_options: []},
      participant_ids: MapSet.new(participant_ids),
      participant_roles: roles,
      connections: %{},
      connection_monitors: %{},
      pending_participant_transfer: nil,
      held_participant_ids: MapSet.new()
    }
  end

  defp attach_command(context, participant_id, connection_id) do
    %AttachConnection{
      id: "cmd-#{connection_id}",
      tenant_id: context.tenant,
      actor_id: "actor-rec-bound",
      room_id: context.room,
      incarnation_id: context.incarnation,
      participant_id: participant_id,
      connection_id: connection_id,
      deadline: DateTime.add(DateTime.utc_now(), 60, :second)
    }
  end

  defp payload_20ms do
    :binary.copy(<<0>>, 480 * 1 * 2)
  end

  test "permitted main attachment binds a recording handoff", context do
    plan =
      plan_with(true, %{"caller" => {"part-caller", :inherit}}, context)

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-caller", "conn-permitted")

    assert {:reply, {:ok, :human, _, :main, _, _, _}, _state} =
             ConnectionLifecycle.attach(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               state
             )

    assert_receive {:test_audio_recording_bound, sink, handoff}, 500
    assert sink == context.sink
    assert %EgressHandoff{connection_id: "conn-permitted"} = handoff
  end

  test "denied main attachment never receives a recording handoff", context do
    plan =
      plan_with(true, %{"caller" => {"part-caller", false}}, context)

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-caller", "conn-denied")

    assert {:reply, {:ok, :human, _, :main, _, _, _}, _state} =
             ConnectionLifecycle.attach(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               state
             )

    refute_receive {:test_audio_recording_bound, _, _}, 200
    refute_received {:mixer_open_requested, "conn-denied"}
  end

  test "permitted transfer preparation binds early so private room assets are captured",
       context do
    plan =
      plan_with(
        true,
        %{
          "caller" => {"part-caller", :inherit},
          "support" => {"part-support", :inherit}
        },
        context
      )

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-support", "conn-transfer-permitted")

    assert {:reply, {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, "att-1"},
            state} =
             ConnectionLifecycle.attach_transfer_preparation(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               "att-1",
               state
             )

    assert_receive {:test_audio_recording_bound, sink, handoff}, 500
    assert sink == context.sink
    assert %EgressHandoff{connection_id: "conn-transfer-permitted"} = handoff

    assert %{admission: :transfer_preparation} =
             Map.fetch!(state.connections, "conn-transfer-permitted")
  end

  test "denied transfer destination never receives a recording handoff even before present",
       context do
    plan =
      plan_with(
        true,
        %{
          "caller" => {"part-caller", :inherit},
          "support" => {"part-support", false}
        },
        context
      )

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-support", "conn-transfer-denied")

    assert {:reply, {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, "att-denied"},
            _state} =
             ConnectionLifecycle.attach_transfer_preparation(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               "att-denied",
               state
             )

    refute_receive {:test_audio_recording_bound, _, _}, 200
    refute_received {:mixer_open_requested, "conn-transfer-denied"}
  end

  test "promotion keeps the preparation binding for a permitted destination", context do
    plan =
      plan_with(
        true,
        %{
          "caller" => {"part-caller", :inherit},
          "support" => {"part-support", :inherit}
        },
        context
      )

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-support", "conn-promote")

    assert {:reply,
            {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, "att-promote"}, state} =
             ConnectionLifecycle.attach_transfer_preparation(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               "att-promote",
               state
             )

    assert_receive {:test_audio_recording_bound, _, _}, 500

    assert {:ok, promoted, promoted_state} =
             ConnectionLifecycle.promote_transfer("att-promote", state)

    assert promoted.admission == :main
    assert promoted.transfer_attempt_id == nil
    assert Map.fetch!(promoted_state.connections, "conn-promote").admission == :main

    # The promoted connection keeps a usable handoff: offering agent and room frames works.
    handoff = :sys.get_state(context.sink).recording_egress
    assert %EgressHandoff{connection_id: "conn-promote"} = handoff

    room_frame = %EgressAcceptedFrame{
      tenant_id: context.tenant,
      room_id: context.room,
      incarnation_id: context.incarnation,
      source_participant_id: "part-agent",
      connection_id: "conn-promote",
      sample_rate: 48_000,
      channels: 1,
      origin: :room,
      payload: payload_20ms()
    }

    assert :ok = EgressHandoff.offer(handoff, room_frame)
    assert_receive {:vxpipe_recording_egress, ^handoff, %{origin: :room}}, 500

    agent_frame = %EgressAcceptedFrame{
      tenant_id: context.tenant,
      room_id: context.room,
      incarnation_id: context.incarnation,
      source_participant_id: "part-agent",
      connection_id: "conn-promote",
      sample_rate: 48_000,
      channels: 1,
      origin: :participant,
      payload: payload_20ms()
    }

    assert :ok = EgressHandoff.offer(handoff, agent_frame)
    assert_receive {:vxpipe_recording_egress, ^handoff, %{origin: :participant}}, 500
  end

  test "promotion never binds a denied destination", context do
    plan =
      plan_with(
        true,
        %{
          "caller" => {"part-caller", :inherit},
          "support" => {"part-support", false}
        },
        context
      )

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-support", "conn-promote-denied")

    assert {:reply,
            {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, "att-deny-promote"},
            state} =
             ConnectionLifecycle.attach_transfer_preparation(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               "att-deny-promote",
               state
             )

    refute_receive {:test_audio_recording_bound, _, _}, 200

    assert {:ok, promoted, promoted_state} =
             ConnectionLifecycle.promote_transfer("att-deny-promote", state)

    assert promoted.admission == :main
    assert Map.fetch!(promoted_state.connections, "conn-promote-denied").admission == :main
    assert :sys.get_state(context.sink).recording_egress == nil
    refute_received {:mixer_open_requested, "conn-promote-denied"}
  end

  test "call-level opt-out binds nothing for any listener", context do
    plan =
      plan_with(false, %{"caller" => {"part-caller", :inherit}}, context)

    state = base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
    command = attach_command(context, "part-caller", "conn-optout")

    assert {:reply, {:ok, :human, _, :main, _, _, _}, _} =
             ConnectionLifecycle.attach(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               state
             )

    refute_receive {:test_audio_recording_bound, _, _}, 200
  end

  test "transfer preparation preserves readiness when the recording path is unavailable",
       context do
    plan =
      plan_with(
        true,
        %{
          "caller" => {"part-caller", :inherit},
          "support" => {"part-support", :inherit}
        },
        context
      )

    failing = start_supervised!({TestRecordingBindingMixer, :unavailable}, id: :unavailable_mixer)

    state = %{
      base_state(context, plan, ["part-caller"], %{"part-caller" => :human})
      | room_mixer: failing
    }

    command = attach_command(context, "part-support", "conn-unavailable")

    assert {:reply,
            {:ok, :human, nil, :transfer_preparation, :disabled, :disabled, "att-unavail"},
            _state} =
             ConnectionLifecycle.attach_transfer_preparation(
               command,
               self(),
               self(),
               context.sink,
               make_ref(),
               false,
               "att-unavail",
               state
             )
  end
end
