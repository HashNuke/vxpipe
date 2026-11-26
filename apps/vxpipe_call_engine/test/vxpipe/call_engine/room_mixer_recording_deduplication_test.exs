defmodule Vxpipe.CallEngine.RoomMixerRecordingDeduplicationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}

  test "room same payload first accepted wins, second arrival order" do
    {mixer, _recording, identity} = start_room("same-b")
    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, "conn-b")
    assert {:ok, second} = RoomMixer.open_recording_egress(mixer, "conn-a")

    payload = encode([1_000, 2_000])
    assert :ok = EgressHandoff.offer(first, egress(identity, "alice", "conn-b", :room, payload))
    assert :ok = EgressHandoff.offer(second, egress(identity, "alice", "conn-a", :room, payload))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_duplicate_frames == 1
    assert chunk.recording_selected_connection_id == "conn-b"
    refute_receive {:test_recording_chunk, "room-track", _extra}

    stats = RoomMixer.stats(mixer)
    assert stats.recording_egress_room_duplicate_frames == 1
    assert stats.recording_egress_agent_duplicate_frames == 0
    assert "conn-b" in stats.recording_egress_selected_connection_ids
  end

  test "room same payload first accepted wins, first arrival order" do
    {mixer, _recording, identity} = start_room("same-a")
    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, "conn-a")
    assert {:ok, second} = RoomMixer.open_recording_egress(mixer, "conn-b")

    payload = encode([1_000, 2_000])
    assert :ok = EgressHandoff.offer(first, egress(identity, "alice", "conn-a", :room, payload))
    assert :ok = EgressHandoff.offer(second, egress(identity, "alice", "conn-b", :room, payload))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_duplicate_frames == 1
    assert chunk.recording_selected_connection_id == "conn-a"
  end

  test "room different payload chooses newest admitted listener in order" do
    {mixer, _recording, identity} = start_room("diff-inorder")
    assert {:ok, handoff_a} = RoomMixer.open_recording_egress(mixer, "conn-a")
    assert {:ok, handoff_b} = RoomMixer.open_recording_egress(mixer, "conn-b")

    assert :ok =
             EgressHandoff.offer(
               handoff_a,
               egress(identity, "alice", "conn-a", :room, encode([1_000, 1_000]))
             )

    assert :ok =
             EgressHandoff.offer(
               handoff_b,
               egress(identity, "alice", "conn-b", :room, encode([2_000, 2_000]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_selected_connection_id == "conn-b"
    assert chunk.recording_duplicate_frames == 1
    assert decode(chunk.payload) == [2_000, 2_000]
  end

  test "room different payload chooses newest admitted listener reversed arrival" do
    {mixer, _recording, identity} = start_room("diff-rev")
    assert {:ok, handoff_a} = RoomMixer.open_recording_egress(mixer, "conn-a")
    assert {:ok, handoff_b} = RoomMixer.open_recording_egress(mixer, "conn-b")

    assert :ok =
             EgressHandoff.offer(
               handoff_b,
               egress(identity, "alice", "conn-b", :room, encode([2_000, 2_000]))
             )

    assert :ok =
             EgressHandoff.offer(
               handoff_a,
               egress(identity, "alice", "conn-a", :room, encode([1_000, 1_000]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_selected_connection_id == "conn-b"
    assert chunk.recording_duplicate_frames == 1
    assert decode(chunk.payload) == [2_000, 2_000]
  end

  test "agent same payload first accepted wins and artifact is stable" do
    {mixer, _recording, identity, agent_stream} = start_agent_room("agent-same")
    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, "listener-1")
    assert {:ok, second} = RoomMixer.open_recording_egress(mixer, "listener-2")

    assert agent_stream.mode == {:individual_track, "agent-1", "agent-1", "agent-egress"}

    payload = encode([7_000, -7_000])

    assert :ok =
             EgressHandoff.offer(
               first,
               egress(identity, "agent-1", "listener-1", :participant, payload)
             )

    assert :ok =
             EgressHandoff.offer(
               second,
               egress(identity, "agent-1", "listener-2", :participant, payload)
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, stream_id, chunk}
    assert stream_id == agent_stream.stream_id
    assert chunk.recording_duplicate_frames == 1
    assert chunk.recording_selected_connection_id == "listener-1"
    refute_receive {:test_recording_chunk, _, _}

    stats = RoomMixer.stats(mixer)
    assert stats.recording_egress_agent_duplicate_frames == 1
    assert stats.recording_egress_room_duplicate_frames == 0
  end

  test "agent different payload chooses newest admitted listener" do
    {mixer, _recording, identity, _agent_stream} = start_agent_room("agent-diff")
    assert {:ok, handoff_1} = RoomMixer.open_recording_egress(mixer, "listener-1")
    assert {:ok, handoff_2} = RoomMixer.open_recording_egress(mixer, "listener-2")

    assert :ok =
             EgressHandoff.offer(
               handoff_2,
               egress(identity, "agent-1", "listener-2", :participant, encode([9, 9]))
             )

    assert :ok =
             EgressHandoff.offer(
               handoff_1,
               egress(identity, "agent-1", "listener-1", :participant, encode([8, 8]))
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, _stream_id, chunk}
    assert chunk.recording_selected_connection_id == "listener-2"
    assert chunk.recording_duplicate_frames == 1
    assert decode(chunk.payload) == [9, 9]
  end

  test "mixer stats bound selected sample to 64 while counting all duplicates" do
    identity = %{
      tenant_id: "tenant-dedupe",
      call_id: "call-many-listeners",
      room_id: "room-many-listeners",
      incarnation_id: "incarnation-many-listeners"
    }

    token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             recording_token: token,
             sample_rate: 8_000,
             channels: 1,
             frame_samples: 2,
             maximum_buffered_timestamps: 128,
             maximum_sink_frames: 128,
             maximum_recording_egress_frames: 128,
             clock: fn -> Process.get(:egress_clock_ms, 0) end,
             clock_origin_ms: 0,
             register: false
           ]},
        id: {:mixer, identity.incarnation_id}
      )

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
        id: {:recording, "many-listeners"}
      )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :room_track}}
    assert {:ok, _resource, :ready} = RoomRecording.readiness(recording)

    handoffs =
      Enum.map(1..70, fn n ->
        conn = "conn-#{n}"
        assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, conn)
        {conn, handoff}
      end)

    Enum.each(handoffs, fn {conn, handoff} ->
      n = conn |> String.split("-") |> List.last() |> String.to_integer()

      assert :ok =
               EgressHandoff.offer(
                 handoff,
                 egress(identity, "alice", conn, :room, encode([n, n]))
               )
    end)

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_receive {:test_recording_chunk, "room-track", chunk}
    assert chunk.recording_duplicate_frames == 69

    stats = RoomMixer.stats(mixer)
    assert stats.recording_egress_room_duplicate_frames == 69
    assert stats.recording_egress_duplicate_frames == 69
    assert length(stats.recording_egress_selected_connection_ids) == 64
  end

  defp start_room(suffix) do
    identity = %{
      tenant_id: "tenant-dedupe",
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

  defp start_agent_room(suffix) do
    identity = %{
      tenant_id: "tenant-dedupe",
      call_id: "call-#{suffix}",
      room_id: "room-#{suffix}",
      incarnation_id: "incarnation-#{suffix}"
    }

    token = make_ref()
    mixer = start_mixer(identity, token)
    :ok = apply_policy(mixer, 0, true, ["agent-1", "alice"])

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(identity) ++
           [
             mixer: mixer,
             recording_token: token,
             targets: [{:individual_tracks, ["agent-1"]}],
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 4
           ]},
        id: {:recording, suffix}
      )

    stable = {:individual_track, "agent-1", "agent-1", "agent-egress"}
    assert :ok = RoomRecording.prepare_tracks(recording, [stable], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, agent_stream}
    assert agent_stream.mode == stable
    {mixer, recording, identity, agent_stream}
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
