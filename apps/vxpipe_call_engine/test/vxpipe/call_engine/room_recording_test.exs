defmodule Vxpipe.CallEngine.RoomRecordingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}

  @identity %{
    tenant_id: "tenant-recording",
    call_id: "call-recording",
    room_id: "room-recording",
    incarnation_id: "incarnation-recording"
  }

  test "offers only permitted full-mix intervals to its injected writer" do
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
             targets: [:full_mix],
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 2
           ]}
      )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, stream}
    assert stream.stream_id == "full-mix"
    assert stream.mode == :full_mix
    assert stream.sample_rate == 8_000
    assert stream.channels == 1

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, 0))
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, 0))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_receive {:test_recording_chunk, "full-mix", first}
    assert first.sequence == 0
    assert first.offset_samples == 0
    assert first.sample_count == 2
    assert first.policy_revision == 0
    assert first.source_participant_ids == ["alice", "bob"]
    assert decode_samples(first.payload) == [4_000, -3_000]

    :ok = apply_policy(mixer, 1, false)
    assert :ok = RoomMixer.push(mixer, frame("alice", 2, 2, 1))
    assert {:ok, %{delivered: 0}} = RoomMixer.flush_through(mixer, 2)
    refute_receive {:test_recording_chunk, "full-mix", _chunk}

    :ok = apply_policy(mixer, 2, true)
    assert :ok = RoomMixer.push(mixer, frame("bob", 2, 4, 2))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 4)

    assert_receive {:test_recording_chunk, "full-mix", resumed}
    assert resumed.sequence == 1
    assert resumed.offset_samples == 4
    assert resumed.policy_revision == 2
    assert decode_samples(resumed.payload) == [3_000, -5_000]

    assert %{accepted_chunks: 2, rejected_chunks: 0, streams: 1} =
             RoomRecording.stats(recording)
  end

  defp start_mixer(recording_token) do
    options =
      Map.to_list(@identity) ++
        [
          recording_token: recording_token,
          sample_rate: 8_000,
          channels: 1,
          frame_samples: 2,
          maximum_buffered_timestamps: 2,
          maximum_sink_frames: 2,
          register: false
        ]

    start_supervised!({RoomMixer, options})
  end

  defp apply_policy(mixer, revision, record_audio?) do
    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["alice", "bob"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: record_audio?,
        save_transcripts: true
      }
    }

    Enforcer.apply(mixer, snapshot, 100)
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
      payload: encode_samples(samples)
    })
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
