defmodule Vxpipe.CallEngine.RoomMixerRecordingPermittedListenerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}

  test "bound room cue is accepted while absent, other room source is rejected" do
    {mixer, _recording, identity} = start_room("permitted-absent", ["alice"])
    assert {:ok, bound} = RoomMixer.open_recording_egress(mixer, "conn-transfer", "support")
    assert {:ok, ordinary} = RoomMixer.open_recording_egress(mixer, "conn-alice")

    # Permitted destination is absent from the policy but holds a live handoff.
    # Its addressed room asset is accepted before promotion.
    Process.put(:egress_clock_ms, 0)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([1, 1]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.source_participant_ids == ["room"]

    # Other-sourced room frame through the same live credential is rejected.
    Process.put(:egress_clock_ms, 20)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "intruder", "conn-transfer", :room, encode([2, 2]))
             )

    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 160)
    refute_receive {:test_recording_chunk, "room-track", _}

    # Present room source still accepted through an ordinary handoff.
    Process.put(:egress_clock_ms, 40)

    assert :ok =
             EgressHandoff.offer(
               ordinary,
               egress(identity, "alice", "conn-alice", :room, encode([3, 3]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 320)
    assert_receive {:test_recording_chunk, "room-track", _}

    # Unbound credential never accepts an absent room source.
    assert {:ok, unbound} = RoomMixer.open_recording_egress(mixer, "conn-denied")
    Process.put(:egress_clock_ms, 60)

    assert :ok =
             EgressHandoff.offer(
               unbound,
               egress(identity, "support", "conn-denied", :room, encode([4, 4]))
             )

    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 480)
    refute_receive {:test_recording_chunk, "room-track", _}
  end

  test "participant origin still requires presence even with a bound listener" do
    identity = %{
      tenant_id: "tenant-permitted",
      call_id: "call-permitted-agent",
      room_id: "room-permitted-agent",
      incarnation_id: "incarnation-permitted-agent"
    }

    token = make_ref()
    mixer = start_mixer(identity, token)
    :ok = apply_policy(mixer, 0, true, ["alice", "agent-1"])
    assert {:ok, bound} = RoomMixer.open_recording_egress(mixer, "conn-transfer", "support")

    # Absent participant source is rejected despite the bound listener.
    Process.put(:egress_clock_ms, 0)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :participant, encode([5, 5]))
             )

    assert %{recording_egress_buffered_timestamps: 0} = RoomMixer.stats(mixer)

    # Present agent source is unaffected and still buffered.
    assert {:ok, agent_handoff} = RoomMixer.open_recording_egress(mixer, "conn-agent")
    Process.put(:egress_clock_ms, 20)

    assert :ok =
             EgressHandoff.offer(
               agent_handoff,
               egress(identity, "agent-1", "conn-agent", :participant, encode([6, 6]))
             )

    assert %{recording_egress_buffered_timestamps: 1} = RoomMixer.stats(mixer)

    # Bound room cue is still accepted alongside the agent frame.
    Process.put(:egress_clock_ms, 40)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([7, 7]))
             )

    assert %{recording_egress_buffered_timestamps: 2} = RoomMixer.stats(mixer)
  end

  test "global gate denial still drops bound room cues" do
    {mixer, _recording, identity} = start_room("permitted-denied", ["alice"])
    assert {:ok, bound} = RoomMixer.open_recording_egress(mixer, "conn-transfer", "support")

    :ok = apply_policy(mixer, 1, false, ["alice"])
    Process.put(:egress_clock_ms, 0)

    assert :ignored =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([7, 7]))
             )

    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 0)
    refute_receive {:test_recording_chunk, "room-track", _}
  end

  test "install_policy retains bound room cue across a presence update" do
    {mixer, _recording, identity} = start_room("permitted-retain", ["alice"])
    assert {:ok, bound} = RoomMixer.open_recording_egress(mixer, "conn-transfer", "support")

    # Buffer a bound cue and an unknown cue at the current recording revision.
    Process.put(:egress_clock_ms, 0)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([8, 8]))
             )

    Process.sleep(10)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "intruder", "conn-transfer", :room, encode([9, 9]))
             )

    # Presence update keeps recording enabled, so the recording interval is
    # unchanged. The bound cue must survive the retain filter.
    :ok = apply_policy(mixer, 1, true, ["alice", "bob"])
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", _}
    refute_receive {:test_recording_chunk, "room-track", _}
  end

  test "revocation drops the bound room cue" do
    {mixer, _recording, identity} = start_room("permitted-revoke", ["alice"])
    assert {:ok, bound} = RoomMixer.open_recording_egress(mixer, "conn-transfer", "support")

    Process.put(:egress_clock_ms, 0)

    assert :ok =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([10, 10]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", _}

    assert :ok = RoomMixer.revoke_recording_egress(mixer, "conn-transfer")

    assert {:error, :stale_handoff} =
             EgressHandoff.offer(
               bound,
               egress(identity, "support", "conn-transfer", :room, encode([11, 11]))
             )

    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 160)
    refute_receive {:test_recording_chunk, "room-track", _}
  end

  defp start_room(suffix, present) do
    identity = %{
      tenant_id: "tenant-permitted",
      call_id: "call-#{suffix}",
      room_id: "room-#{suffix}",
      incarnation_id: "incarnation-#{suffix}"
    }

    token = make_ref()
    mixer = start_mixer(identity, token)
    :ok = apply_policy(mixer, 0, true, present)

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
end
