defmodule Vxpipe.CallEngine.RoomRecordingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}

  @identity %{
    tenant_id: "tenant-recording",
    call_id: "call-recording",
    room_id: "room-recording",
    incarnation_id: "incarnation-recording"
  }

  test "prepares required track writers before audio and retains them through policy changes" do
    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)
    recording = start_recording(mixer, token, [:room_track, {:individual_tracks, ["alice"]}])
    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :room_track}}
    assert {:ok, pending, :preparing} = RoomRecording.readiness(recording)
    alice = {:individual_track, "alice", "connection-alice", "track-alice"}

    assert {:error, :invalid_recording_tracks} =
             RoomRecording.prepare_tracks(recording, [{:individual_track, "bob", "c", "t"}], 0)

    refute_receive {:test_recording_writer_opened, _caller, ^recording, _stream}
    assert :ok = RoomRecording.prepare_tracks(recording, [alice, :room_track], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: ^alice}}
    refute_receive {:test_recording_chunk, _stream_id, _chunk}
    assert {:ok, resource, :ready} = RoomRecording.readiness(recording)
    assert resource.kind == :recording
    assert resource.scope == :room
    assert resource.generation == pending.generation
    assert :ok = RoomRecording.prepare_tracks(recording, [alice, :room_track], 0)
    assert {:ok, ^resource, :ready} = RoomRecording.readiness(recording)
    refute_receive {:test_recording_writer_opened, _caller, ^recording, _stream}

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    refute_receive {:test_recording_chunk, "room-track", _chunk}
    assert_receive {:test_recording_chunk, _individual, _chunk}
    refute_receive {:test_recording_writer_opened, _caller, ^recording, _stream}
    assert {:ok, ^resource, :ready} = RoomRecording.readiness(recording)

    :ok = apply_policy(mixer, 1, true, transcript_routes: %{})
    assert {:ok, ^resource, :ready} = RoomRecording.readiness(recording)
    :ok = apply_policy(mixer, 2, false)
    assert {:ok, _changed, :preparing} = RoomRecording.readiness(recording)
    assert {:error, :stale_recording_policy} = RoomRecording.prepare_tracks(recording, [alice], 0)

    assert {:error, :recording_not_permitted} =
             RoomRecording.prepare_tracks(recording, [alice, :room_track], 2)

    assert :ok = RoomRecording.prepare_tracks(recording, [], 2)
    assert {:ok, _silent, :ready} = RoomRecording.readiness(recording)

    :ok = apply_policy(mixer, 3, true)
    assert :ok = RoomRecording.prepare_tracks(recording, [alice, :room_track], 3)
    assert {:ok, restored, :ready} = RoomRecording.readiness(recording)
    assert restored.generation == resource.generation
    assert restored.configuration == resource.configuration
    assert restored.policy_interval == 3
    refute_receive {:test_recording_writer_opened, _caller, ^recording, _stream}
  end

  test "a known failed local writer blocks a running recorder" do
    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)
    readiness = :atomics.new(1, [])
    recording = start_recording(mixer, token, [:room_track], readiness: readiness)
    assert {:ok, resource, :ready} = RoomRecording.readiness(recording)
    :ok = :atomics.put(readiness, 1, 1)
    assert {:ok, ^resource, :failed} = RoomRecording.readiness(recording)
    assert %{streams: 1} = RoomRecording.stats(recording)
  end

  test "malformed writer evidence cannot make a required recording resource ready" do
    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)

    recording =
      start_recording(mixer, token, [:room_track],
        readiness_reply: {:ok, %{policy_interval: nil}, :ready}
      )

    assert {:ok, _resource, :failed} = RoomRecording.readiness(recording)
  end

  test "a partial preparation retains opened writers and never opens a missing writer on audio" do
    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)
    alice = {:individual_track, "alice", "connection-alice", "track-alice"}
    bob = {:individual_track, "bob", "connection-bob", "track-bob"}
    failure = :atomics.new(1, [])
    :ok = :atomics.put(failure, 1, 1)

    recording =
      start_recording(mixer, token, [{:individual_tracks, ["alice", "bob"]}],
        failure: failure,
        fail_mode: bob
      )

    assert {:error, :test_open_failed} = RoomRecording.prepare_tracks(recording, [alice, bob], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: ^alice}}
    assert_receive {:test_recording_writer_rejected, ^bob}
    assert {:ok, _resource, :preparing} = RoomRecording.readiness(recording)

    :ok = :atomics.put(failure, 1, 0)
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    refute_receive {:test_recording_writer_opened, _caller, ^recording, _stream}
    refute_receive {:test_recording_chunk, _stream, _chunk}
    assert %{streams: 1, rejected_chunks: 1} = RoomRecording.stats(recording)

    assert :ok = RoomRecording.prepare_tracks(recording, [alice, bob], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: ^bob}}
    refute_receive {:test_recording_writer_opened, _caller, ^recording, _duplicate}
    assert {:ok, _resource, :ready} = RoomRecording.readiness(recording)
    assert :ok = RoomMixer.push(mixer, frame("bob", 2, 2, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 2)
    assert_receive {:test_recording_chunk, _stream, %{sequence: 0, offset_samples: 2}}
  end

  test "room-origin egress lands on the room track while participant ingress stays on its own track" do
    recording_token = make_ref()
    mixer = start_mixer(recording_token)
    :ok = apply_policy(mixer, 0, true)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(@identity) ++
           [
             mixer: mixer,
             recording_token: recording_token,
             targets: [:room_track, {:individual_tracks, ["alice"]}],
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 2
           ]}
      )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, stream}
    assert stream.stream_id == "room-track"
    assert stream.mode == :room_track
    assert stream.sample_rate == 8_000
    assert stream.channels == 1

    alice = {:individual_track, "alice", "connection-alice", "track-alice"}
    assert :ok = RoomRecording.prepare_tracks(recording, [alice, :room_track], 0)

    assert_receive {:test_recording_writer_opened, _caller, ^recording, individual_stream}

    assert individual_stream.mode == alice
    assert individual_stream.participant_id == "alice"
    assert individual_stream.connection_id == "connection-alice"
    assert individual_stream.track_id == "track-alice"
    assert individual_stream.reconnection == 0

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, 0))
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, 0))
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, "connection-alice")
    assert :ok = EgressHandoff.offer(handoff, egress("alice", "connection-alice", :room))
    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", room}
    assert room.sequence == 0
    assert room.offset_samples == 0
    assert room.sample_count == 2
    assert room.policy_revision == 0
    assert room.source_participant_ids == ["room"]

    assert_receive {:test_recording_chunk, individual_stream_id, individual}
    assert individual_stream_id == individual_stream.stream_id
    assert individual.sequence == 0
    assert individual.offset_samples == 0
    assert individual.source_participant_ids == ["alice"]
    assert decode_samples(individual.payload) == [1_000, 2_000]

    # A denied interval silences every track, including the room track.
    :ok = apply_policy(mixer, 1, false)
    assert :ok = RoomMixer.push(mixer, frame("alice", 2, 2, 1))
    assert :ignored = EgressHandoff.offer(handoff, egress("alice", "connection-alice", :room))
    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 2)
    refute_receive {:test_recording_chunk, "room-track", _chunk}

    :ok = apply_policy(mixer, 2, true)
    Process.put(:egress_clock_ms, 5)
    assert {:ok, handoff2} = RoomMixer.open_recording_egress(mixer, "connection-alice-2")
    assert :ok = RoomMixer.push(mixer, frame("bob", 2, 4, 2))
    assert :ok = EgressHandoff.offer(handoff2, egress("alice", "connection-alice-2", :room))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 40)

    refute_receive {:test_recording_writer_opened, _caller, ^recording, %{participant_id: "bob"}}

    assert_receive {:test_recording_chunk, "room-track", resumed}
    assert resumed.sequence == 1
    assert resumed.offset_samples == 40
    assert resumed.policy_revision == 2
    assert resumed.source_participant_ids == ["room"]

    assert %{accepted_chunks: 3, rejected_chunks: 0, streams: 2} =
             RoomRecording.stats(recording)
  end

  test "a duplicate room frame on a second connection is counted, not written" do
    recording_token = make_ref()
    mixer = start_mixer(recording_token)
    :ok = apply_policy(mixer, 0, true)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(@identity) ++
           [
             mixer: mixer,
             recording_token: recording_token,
             targets: [:room_track],
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 2
           ]}
      )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :room_track}}
    assert {:ok, _resource, :ready} = RoomRecording.readiness(recording)

    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, "connection-first")
    assert {:ok, second} = RoomMixer.open_recording_egress(mixer, "connection-second")
    assert :ok = EgressHandoff.offer(first, egress("alice", "connection-first", :room))
    assert :ok = EgressHandoff.offer(second, egress("alice", "connection-second", :room))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "room-track", _chunk}
    refute_receive {:test_recording_chunk, "room-track", _duplicate}

    stats = RoomMixer.stats(mixer)
    assert stats.recording_egress_buffered_timestamps == 0
    assert stats.recording_egress_pending_frames == 0
    assert stats.recording_egress_room_duplicate_frames == 1
  end

  test "a reconnected participant opens a suffixed track without renumbering the first" do
    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)
    recording = start_recording(mixer, token, [{:individual_tracks, ["alice"]}])
    first = {:individual_track, "alice", "connection-alice", "track-alice"}
    assert :ok = RoomRecording.prepare_tracks(recording, [first], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, first_stream}
    assert first_stream.reconnection == 0

    second = {:individual_track, "alice", "connection-alice-2", "track-alice-2"}
    assert :ok = RoomRecording.prepare_tracks(recording, [first, second], 0)
    assert_receive {:test_recording_writer_opened, _caller, ^recording, second_stream}
    assert second_stream.mode == second
    assert second_stream.reconnection == 1
    assert second_stream.participant_id == "alice"
  end

  defp start_mixer(recording_token) do
    options =
      Map.to_list(@identity) ++
        [
          recording_token: recording_token,
          sample_rate: 8_000,
          channels: 1,
          frame_samples: 2,
          maximum_buffered_timestamps: 4,
          maximum_sink_frames: 8,
          clock: fn -> Process.get(:egress_clock_ms, 0) end,
          clock_origin_ms: 0,
          register: false
        ]

    start_supervised!({RoomMixer, options})
  end

  defp start_recording(mixer, token, targets, writer_options \\ []) do
    start_supervised!(
      {RoomRecording,
       Map.to_list(@identity) ++
         [
           mixer: mixer,
           recording_token: token,
           targets: targets,
           writer: {TestRecordingWriter, Keyword.put(writer_options, :observer, self())},
           maximum_pull_frames: 2
         ]}
    )
  end

  defp apply_policy(mixer, revision, record_audio?, options \\ []) do
    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["alice", "bob"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: Keyword.get(options, :transcript_routes, :unrestricted),
        record_audio: record_audio?,
        save_transcripts: true
      }
    }

    Enforcer.apply(mixer, snapshot, 1_000)
  end

  defp frame(source, sequence, timestamp, revision) do
    samples = if source == "alice", do: [1_000, 2_000], else: [3_000, -5_000]

    struct!(NormalizedFrame, %{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: "connection-#{source}",
      track_id: "track-#{source}",
      sequence_number: sequence,
      timestamp: timestamp,
      policy_revision: revision,
      sample_rate: 8_000,
      channels: 1,
      origin: :participant,
      payload: encode_samples(samples)
    })
  end

  defp egress(source, connection_id, origin) do
    %EgressAcceptedFrame{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection_id,
      sample_rate: 8_000,
      channels: 1,
      origin: origin,
      payload: encode_samples([7_000, -7_000])
    }
  end

  defp encode_samples(samples) do
    Enum.reduce(samples, <<>>, fn sample, payload ->
      <<payload::binary, sample::little-signed-16>>
    end)
  end

  defp decode_samples(payload) do
    for <<sample::little-signed-16 <- payload>>, do: sample
  end
end
