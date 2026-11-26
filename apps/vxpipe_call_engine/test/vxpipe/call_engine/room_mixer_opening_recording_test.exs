defmodule Vxpipe.CallEngine.RoomMixerOpeningRecordingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.{EgressAcceptedFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer

  @identity %{
    tenant_id: "tenant-opening-rec",
    room_id: "room-opening-rec",
    incarnation_id: "incarnation-opening-rec"
  }

  test "tracks permitted room opening before gate while blocking early participant audio" do
    Process.put(:egress_clock_ms, 0)
    mixer = start_mixer(awaiting_opening_audio: true)
    :ok = apply_policy(mixer, 0, true, ["caller", "agent"])

    assert {:ok, room_sub} = subscribe_recording(mixer, "rec-room", :room_track)

    assert {:ok, individual_sub} =
             subscribe_recording(
               mixer,
               "rec-individual",
               {:individual_tracks, ["caller", "agent"]}
             )

    assert {:ok, caller_handoff} = RoomMixer.open_recording_egress(mixer, "conn-caller")
    assert {:ok, agent_handoff} = RoomMixer.open_recording_egress(mixer, "conn-agent")

    opening = encode([1_111, 1_111])
    early_caller = encode([9_991, 9_991])
    early_agent = encode([9_992, 9_992])

    # Eligible permitted room asset before gate release (opening greeting).
    assert :ok =
             EgressHandoff.offer(
               caller_handoff,
               egress("caller", "conn-caller", :room, opening)
             )

    # Early participant ingress and agent audio stay blocked.
    assert :ok =
             EgressHandoff.offer(
               caller_handoff,
               egress("caller", "conn-caller", :participant, early_caller)
             )

    assert :ok =
             EgressHandoff.offer(
               agent_handoff,
               egress("agent", "conn-agent", :participant, early_agent)
             )

    assert :ok = RoomMixer.push(mixer, ingress("caller", "conn-caller", 1, 0, early_caller))
    assert :ok = RoomMixer.push(mixer, ingress("agent", "conn-agent", 1, 0, early_agent))

    # Drain async recording-egress messages before flushing.
    _ = :sys.get_state(mixer)

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    # Room opening is externally observable on the room track.
    assert {:ok, [room_frame]} = RoomMixer.take(room_sub, 4)
    assert room_frame.mode == :room_track
    assert room_frame.source_participant_ids == ["room"]
    assert decode(room_frame.payload) == [1_111, 1_111]

    # No early participant audio leaks to individual tracks.
    assert {:ok, []} = RoomMixer.take(individual_sub, 4)

    # Release the gate: actual opening playout completed.
    Process.put(:egress_clock_ms, 40)
    assert :ok = RoomMixer.complete_opening(mixer)

    wait = encode([2_222, 2_222])
    caller = encode([3_333, 3_333])
    agent = encode([4_444, 4_444])
    reconnect = encode([5_555, 5_555])

    assert {:ok, reconnect_handoff} = RoomMixer.open_recording_egress(mixer, "conn-caller-1")

    assert :ok =
             EgressHandoff.offer(caller_handoff, egress("caller", "conn-caller", :room, wait))

    assert :ok = RoomMixer.push(mixer, ingress("caller", "conn-caller", 2, 320, caller))

    assert :ok =
             EgressHandoff.offer(
               agent_handoff,
               egress("agent", "conn-agent", :participant, agent)
             )

    assert :ok =
             EgressHandoff.offer(
               reconnect_handoff,
               egress("caller", "conn-caller-1", :participant, reconnect)
             )

    _ = :sys.get_state(mixer)
    assert {:ok, %{delivered: _}} = RoomMixer.flush_through(mixer, 400)

    assert {:ok, room_frames} = RoomMixer.take(room_sub, 4)
    assert Enum.any?(room_frames, &(decode(&1.payload) == [2_222, 2_222]))

    assert {:ok, individual_frames} = RoomMixer.take(individual_sub, 8)
    payloads = Enum.map(individual_frames, &decode(&1.payload))

    assert [3_333, 3_333] in payloads
    assert [4_444, 4_444] in payloads
    assert [5_555, 5_555] in payloads
    refute [9_991, 9_991] in payloads
    refute [9_992, 9_992] in payloads
    refute [1_111, 1_111] in payloads
  end

  test "pre-gate room assets still require static permission and live gate plus presence" do
    Process.put(:egress_clock_ms, 0)
    mixer = start_mixer(awaiting_opening_audio: true)
    :ok = apply_policy(mixer, 0, false, ["caller", "agent"])

    assert {:ok, room_sub} = subscribe_recording(mixer, "rec-room-denied", :room_track)
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, "conn-caller")

    # Live gate denies: effective record_audio is false, so the offer is ignored
    # at the static handoff gate and never reaches the mixer.
    assert :ignored =
             EgressHandoff.offer(
               handoff,
               egress("caller", "conn-caller", :room, encode([1_111, 1_111]))
             )

    _ = :sys.get_state(mixer)
    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 0)
    assert {:ok, []} = RoomMixer.take(room_sub, 4)

    # Listener/source presence: permitted interval but unknown source is dropped
    # at the live mixer gate even though the static gate allows it.
    :ok = apply_policy(mixer, 1, true, ["caller", "agent"])
    Process.put(:egress_clock_ms, 40)
    assert {:ok, handoff2} = RoomMixer.open_recording_egress(mixer, "conn-ghost")

    assert :ok =
             EgressHandoff.offer(
               handoff2,
               egress("ghost", "conn-ghost", :room, encode([2_222, 2_222]))
             )

    _ = :sys.get_state(mixer)
    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 400)
    assert {:ok, []} = RoomMixer.take(room_sub, 4)
  end

  defp start_mixer(overrides) do
    base = [
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      sample_rate: 8_000,
      channels: 1,
      frame_samples: 2,
      maximum_buffered_timestamps: 8,
      maximum_sink_frames: 8,
      recording_token: make_ref(),
      clock: fn -> Process.get(:egress_clock_ms, 0) end,
      clock_origin_ms: 0,
      register: false
    ]

    start_supervised!({RoomMixer, Keyword.merge(base, overrides)})
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

  defp subscribe_recording(mixer, id, mode) do
    RoomMixer.subscribe_recording(mixer,
      id: id,
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      recording_token: recording_token(mixer),
      mode: mode,
      subscriber: self()
    )
  end

  defp recording_token(mixer) do
    :sys.get_state(mixer).recording_token
  end

  defp ingress(source, connection_id, sequence, timestamp, payload) do
    struct!(NormalizedFrame, %{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection_id,
      track_id: "track-#{connection_id}",
      sequence_number: sequence,
      timestamp: timestamp,
      policy_revision: 0,
      sample_rate: 8_000,
      channels: 1,
      origin: :participant,
      payload: payload
    })
  end

  defp egress(source, connection_id, origin, payload) do
    %EgressAcceptedFrame{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
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
