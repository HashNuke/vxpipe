defmodule Vxpipe.CallEngine.RoomMixerRecordingRevocationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}

  test "detached listener handoff is invalidated before enqueue and re-entry uses fresh credential" do
    {mixer, _recording, identity} = start_room("revoke-stale")
    assert {:ok, stale} = RoomMixer.open_recording_egress(mixer, "conn-stale")

    payload = encode([1_000, 2_000])

    assert :ok =
             EgressHandoff.offer(stale, egress(identity, "alice", "conn-stale", :room, payload))

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", _chunk}

    # Detachment invalidates the stale credential before any further enqueue.
    assert :ok = RoomMixer.revoke_recording_egress(mixer, "conn-stale")

    # Stale offer must not queue PCM.
    assert {:error, :stale_handoff} =
             EgressHandoff.offer(stale, egress(identity, "alice", "conn-stale", :room, payload))

    refute_receive {:vxpipe_recording_egress, ^stale, _frame}, 100
    refute_receive {:test_recording_chunk, "room-track", _chunk2}, 100

    # Re-entry with the same connection id gets a fresh credential that works.
    Process.put(:egress_clock_ms, 20)
    assert {:ok, fresh} = RoomMixer.open_recording_egress(mixer, "conn-stale")
    refute EgressHandoff.id(stale) == EgressHandoff.id(fresh)

    assert :ok =
             EgressHandoff.offer(fresh, egress(identity, "alice", "conn-stale", :room, payload))

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 160)
    assert_receive {:test_recording_chunk, "room-track", _fresh_chunk}

    # The stale credential stays invalid after re-entry.
    assert {:error, :stale_handoff} =
             EgressHandoff.offer(stale, egress(identity, "alice", "conn-stale", :room, payload))

    _ = EgressHandoff.release(stale)
    _ = EgressHandoff.release(fresh)
  end

  test "reopened connection gets newest admission rank and wins" do
    {mixer, _recording, identity} = start_room("revoke-reopen-rank")
    assert {:ok, _a} = RoomMixer.open_recording_egress(mixer, "conn-a")
    assert {:ok, b} = RoomMixer.open_recording_egress(mixer, "conn-b")
    assert :ok = RoomMixer.revoke_recording_egress(mixer, "conn-a")

    Process.put(:egress_clock_ms, 20)
    assert {:ok, fresh_a} = RoomMixer.open_recording_egress(mixer, "conn-a")

    assert :ok =
             EgressHandoff.offer(
               b,
               egress(identity, "alice", "conn-b", :room, encode([2_000, 2_000]))
             )

    assert :ok =
             EgressHandoff.offer(
               fresh_a,
               egress(identity, "alice", "conn-a", :room, encode([1_000, 1_000]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 160)
    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_selected_connection_id == "conn-a"
    assert decode(chunk.payload) == [1_000, 1_000]
  end

  test "failed second bind revokes only the new handoff and preserves eligible room cue" do
    {mixer, _recording, identity} = start_room("revoke-failed-bind")
    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, "conn-first")
    assert {:ok, second} = RoomMixer.open_recording_egress(mixer, "conn-first")

    # Simulate a failed attachment/promotion bind: only the new credential is revoked.
    assert :ok = RoomMixer.revoke_recording_handoff(mixer, second)

    payload = encode([3_000, 4_000])

    assert {:error, :stale_handoff} =
             EgressHandoff.offer(second, egress(identity, "alice", "conn-first", :room, payload))

    # Eligible initial cue on the preserved credential still records.
    assert :ok =
             EgressHandoff.offer(first, egress(identity, "alice", "conn-first", :room, payload))

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", _chunk}
  end

  test "invalidated handoff preserves eligible room origin and queues no PCM" do
    counters = EgressHandoff.new_counters()
    :ok = EgressHandoff.install_policy(counters, 0, true)

    identity = %{
      tenant_id: "tenant-revoke",
      room_id: "room-revoke",
      incarnation_id: "incarnation-revoke"
    }

    config = %{
      channels: 1,
      clock: fn -> 0 end,
      clock_origin_ms: 0,
      frame_samples: 960,
      gate: counters,
      sample_rate: 48_000
    }

    handoff =
      EgressHandoff.new(self(), make_ref(), identity, config, "conn-direct", 4, counters)

    room_frame = %EgressAcceptedFrame{
      tenant_id: identity.tenant_id,
      room_id: identity.room_id,
      incarnation_id: identity.incarnation_id,
      source_participant_id: "caller",
      connection_id: "conn-direct",
      sample_rate: 48_000,
      channels: 1,
      origin: :room,
      payload: :binary.copy(<<1, 0>>, 960)
    }

    participant_frame = %{room_frame | source_participant_id: "agent", origin: :participant}

    # Eligible room-origin cue is offered with origin preserved; participant
    # origin is preserved on the same live credential for the egress gate.
    assert :ok = EgressHandoff.offer(handoff, room_frame)
    assert_receive {:vxpipe_recording_egress, ^handoff, %{origin: :room}}

    assert :ok = EgressHandoff.offer(handoff, participant_frame)
    assert_receive {:vxpipe_recording_egress, ^handoff, %{origin: :participant}}

    # After invalidation no PCM is queued.
    :ok = EgressHandoff.invalidate(handoff)

    assert {:error, :stale_handoff} = EgressHandoff.offer(handoff, room_frame)
    refute_receive {:vxpipe_recording_egress, ^handoff, _frame2}, 100
    :ok = EgressHandoff.release(handoff)
    :ok = EgressHandoff.release(handoff)
  end

  test "lifecycle detachment revokes the sink-held credential" do
    alias Vxpipe.CallEngine.Archive.Recorder
    alias Vxpipe.CallEngine.Command.AttachConnection
    alias Vxpipe.CallEngine.ResolvedCallPlan
    alias Vxpipe.CallEngine.Room.Snapshot
    alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, FirstMessage, OpeningAudio, State}
    alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime

    tenant = "tenant-lifecycle-revoke"
    room = "room-lifecycle-revoke"
    incarnation = "incarnation-lifecycle-revoke"

    token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         [
           tenant_id: tenant,
           room_id: room,
           incarnation_id: incarnation,
           recording_token: token,
           sample_rate: 8_000,
           channels: 1,
           frame_samples: 2,
           maximum_buffered_timestamps: 8,
           maximum_sink_frames: 8,
           register: false
         ]},
        id: :lifecycle_mixer_revoke
      )

    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})

    plan = %ResolvedCallPlan{
      call_spec_id: "spec-revoke",
      call_spec_revision: 1,
      schema_version: "1",
      tenant_id: tenant,
      actor_id: "actor-revoke",
      call_id: "call-revoke",
      room_id: room,
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "caller",
      opening_audio: nil,
      media_policy: %ResolvedCallPlan.MediaPolicy{
        audio_routes: :inherit,
        transcript_routes: :inherit,
        record_audio: true,
        save_transcripts: :inherit
      },
      participants: %{
        "caller" => %ResolvedCallPlan.Participant{
          call_spec_key: "caller",
          participant_id: "part-caller",
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
            record_audio: :inherit,
            save_transcripts: :inherit
          },
          tools: %{},
          transfers: [],
          transfer_history: nil,
          variable_permissions: %{}
        }
      },
      transfer_policy: %Vxpipe.CallEngine.CallSpec.TransferPolicy{attempt_timeout_ms: 30_000},
      call_variables: %{},
      tool_visibility: %{},
      max_duration_ms: 60_000
    }

    snapshot = %Snapshot{
      tenant_id: tenant,
      room_id: room,
      incarnation_id: incarnation,
      lifecycle: :open,
      created_by_actor_id: "actor-revoke",
      created_by_command_id: "cmd-room"
    }

    state = %State{
      archive_recorder: %Recorder{port: nil, participant_activations: %{}},
      call_lifecycle: nil,
      first_message: FirstMessage.completed(),
      media_policy_authority: nil,
      opening_audio: OpeningAudio.open(),
      room_mixer: mixer,
      transcript_router: nil,
      snapshot: snapshot,
      speech_to_text_runtime: %{},
      startup_ready?: true,
      text_capability_required?: false,
      participant_transfer_runtime: %Runtime{plan: plan, startup_options: []},
      participant_ids: MapSet.new(["part-caller"]),
      participant_roles: %{"part-caller" => :human},
      connections: %{},
      connection_monitors: %{},
      pending_participant_transfer: nil,
      held_participant_ids: MapSet.new()
    }

    command = %AttachConnection{
      id: "cmd-conn-revoke",
      tenant_id: tenant,
      actor_id: "actor-revoke",
      room_id: room,
      incarnation_id: incarnation,
      participant_id: "part-caller",
      connection_id: "conn-lifecycle-revoke",
      deadline: DateTime.add(DateTime.utc_now(), 60, :second)
    }

    assert {:reply, {:ok, :human, _, :main, _, _, _}, attached} =
             ConnectionLifecycle.attach(command, self(), self(), sink, make_ref(), false, state)

    bound = :sys.get_state(sink).recording_egress
    assert %EgressHandoff{connection_id: "conn-lifecycle-revoke"} = bound
    assert EgressHandoff.valid?(bound)

    detach = %{command | id: "cmd-detach-revoke"}

    assert {:reply, :ok, detached} = ConnectionLifecycle.detach(detach, self(), self(), attached)
    refute Map.has_key?(detached.connections, "conn-lifecycle-revoke")

    # The sink-held credential is invalidated on detachment, so it queues no PCM.
    refute EgressHandoff.valid?(bound)

    stale_frame = %EgressAcceptedFrame{
      tenant_id: tenant,
      room_id: room,
      incarnation_id: incarnation,
      source_participant_id: "part-caller",
      connection_id: "conn-lifecycle-revoke",
      sample_rate: 8_000,
      channels: 1,
      origin: :room,
      payload: encode([5_000, 6_000])
    }

    assert {:error, :stale_handoff} = EgressHandoff.offer(bound, stale_frame)
  end

  defp start_room(suffix) do
    identity = %{
      tenant_id: "tenant-revoke",
      call_id: "call-#{suffix}",
      room_id: "room-#{suffix}",
      incarnation_id: "incarnation-#{suffix}"
    }

    token = make_ref()
    mixer = start_mixer(identity, token)
    :ok = apply_policy(mixer, 0, true, ["alice", "bob"])

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(identity) ++
           [
             mixer: mixer,
             recording_token: token,
             targets: [:room_track],
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 4
           ]},
        id: {:recording, suffix}
      )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :room_track}}
    assert {:ok, _resource, :ready} = RoomRecording.readiness(recording)
    {mixer, recording, identity}
  end

  defp start_mixer(identity, recording_token) do
    start_supervised!(
      {RoomMixer,
       Map.to_list(identity) ++
         [
           recording_token: recording_token,
           sample_rate: 8_000,
           channels: 1,
           frame_samples: 2,
           maximum_buffered_timestamps: 8,
           maximum_sink_frames: 8,
           clock: fn -> Process.get(:egress_clock_ms, 0) end,
           clock_origin_ms: 0,
           register: false
         ]},
      id: {:mixer, identity.incarnation_id}
    )
  end

  defp apply_policy(mixer, revision, record_audio?, present) do
    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(present),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: record_audio?,
        save_transcripts: true
      }
    }

    Enforcer.apply(mixer, snapshot, 1_000)
  end

  defp egress(identity, source, connection_id, origin, payload) do
    %EgressAcceptedFrame{
      tenant_id: identity.tenant_id,
      room_id: identity.room_id,
      incarnation_id: identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection_id,
      sample_rate: 8_000,
      channels: 1,
      origin: origin,
      payload: payload
    }
  end

  defp encode(samples) do
    Enum.reduce(samples, <<>>, fn sample, payload ->
      <<payload::binary, sample::little-signed-16>>
    end)
  end

  defp decode(payload) do
    for <<sample::little-signed-16 <- payload>>, do: sample
  end
end
