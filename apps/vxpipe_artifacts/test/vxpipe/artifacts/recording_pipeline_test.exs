defmodule Vxpipe.Artifacts.RecordingPipelineTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.{RecordingWriter, TestObjectStore}
  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording}

  @identity %{
    tenant_id: "tenant-recording-pipeline",
    call_id: "call-recording-pipeline",
    room_id: "room-recording-pipeline",
    incarnation_id: "incarnation-recording-pipeline"
  }

  test "exposes required writer and subscription instances so writer loss revokes the barrier" do
    if is_nil(Process.whereis(Vxpipe.CallEngine.ReadinessTaskSupervisor)) do
      start_supervised!({Task.Supervisor, name: Vxpipe.CallEngine.ReadinessTaskSupervisor})
    end

    token = make_ref()
    mixer = start_mixer(token)
    :ok = apply_policy(mixer, 0, true)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(@identity) ++
           [
             mixer: mixer,
             recording_token: token,
             targets: [:full_mix],
             writer:
               {RecordingWriter,
                [
                  object_store: TestObjectStore,
                  object_store_options: [observer: self()],
                  maximum_pending_chunks: 2,
                  drain_timeout_ms: 1_000
                ]},
             maximum_pull_frames: 4
           ]}
      )

    assert {:ok, resources} = RoomRecording.readiness_resources(recording)

    assert Enum.sort(Enum.map(resources, & &1.kind)) ==
             [:recording, :recording_subscription, :recording_writer]

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: @identity.incarnation_id,
         attempt_id: "recording-writer-loss",
         resources: resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    writer = Enum.find(resources, &(&1.kind == :recording_writer)).instance
    monitor = Process.monitor(writer)
    Process.exit(writer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^writer, :killed}
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000
    assert %{streams: 1} = RoomRecording.stats(recording)
    assert {:error, :unavailable} = RoomRecording.readiness(recording)
  end

  test "keeps live output responsive and stores only accepted recording intervals" do
    recording_token = make_ref()
    mixer = start_mixer(recording_token)
    :ok = apply_policy(mixer, 0, true)
    monitor = subscribe_monitor(mixer)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(@identity) ++
           [
             mixer: mixer,
             recording_token: recording_token,
             targets: [:full_mix],
             writer:
               {RecordingWriter,
                [
                  object_store: TestObjectStore,
                  object_store_options: [observer: self()],
                  maximum_pending_chunks: 2,
                  drain_timeout_ms: 1_000,
                  observer: self()
                ]},
             maximum_pull_frames: 4
           ]}
      )

    assert_receive {:test_object_store_opened, _task, spec}
    assert spec.kind == :full_mix
    assert {:ok, ready, :ready} = RoomRecording.readiness(recording)

    first_mix = [4_000, -3_000]
    flush_mix(mixer, 1, 0, 0, [1_000, 2_000], [3_000, -5_000])
    assert_monitor(monitor, first_mix, 0)

    assert_receive {:test_object_store_write, first_task, first_reference, first_chunk}
    assert first_chunk.sequence == 0
    assert first_chunk.offset_samples == 0
    assert decode_samples(first_chunk.payload) == first_mix

    :ok = apply_policy(mixer, 1, false)
    denied_mix = [1_200, 1_400]
    flush_mix(mixer, 2, 2, 1, [500, 600], [700, 800])
    assert_monitor(monitor, denied_mix, 0)
    refute_receive {:test_object_store_write, _task, _reference, _chunk}

    :ok = apply_policy(mixer, 2, true)
    second_mix = [40, 60]
    flush_mix(mixer, 3, 4, 2, [10, 20], [30, 40])
    assert_monitor(monitor, second_mix, 0)

    rejected_mix = [120, 140]
    flush_mix(mixer, 4, 6, 2, [50, 60], [70, 80])
    assert_monitor(monitor, rejected_mix, 0)

    _state = :sys.get_state(recording)

    assert %{accepted_chunks: 2, rejected_chunks: 1} = RoomRecording.stats(recording)
    assert {:ok, saturated, :ready} = RoomRecording.readiness(recording)
    assert saturated.generation == ready.generation
    assert saturated.configuration == ready.configuration
    assert saturated.policy_interval == 2

    send(first_task, {:test_object_store_continue, first_reference})

    assert_receive {:test_object_store_write, second_task, second_reference, second_chunk}
    assert second_chunk.sequence == 1
    assert second_chunk.offset_samples == 4
    assert decode_samples(second_chunk.payload) == second_mix

    final_mix = [50, 225]
    flush_mix(mixer, 5, 8, 2, [100, 200], [-50, 25])
    assert_monitor(monitor, final_mix, 0)

    _state = :sys.get_state(recording)

    assert %{accepted_chunks: 3, rejected_chunks: 1} = RoomRecording.stats(recording)

    send(second_task, {:test_object_store_continue, second_reference})

    assert_receive {:test_object_store_write, third_task, third_reference, third_chunk}
    assert third_chunk.sequence == 3
    assert third_chunk.offset_samples == 8
    assert decode_samples(third_chunk.payload) == final_mix
    send(third_task, {:test_object_store_continue, third_reference})

    recording_monitor = Process.monitor(recording)
    GenServer.stop(recording, :normal)
    assert_receive {:DOWN, ^recording_monitor, :process, ^recording, :normal}

    assert_receive {:test_object_store_completed, _task, manifest}
    assert manifest.started_offset_samples == 0
    assert manifest.ended_offset_samples == 10
    assert manifest.sample_count == 6
    assert manifest.accepted_chunks == 3
    assert manifest.rejected_chunks == 1

    assert manifest.gaps == [
             %{offset_samples: 2, sample_count: 2},
             %{offset_samples: 6, sample_count: 2}
           ]

    assert manifest.status == :incomplete

    assert_receive {:vxpipe_artifact_writer_finished, _writer, result}
    assert result.manifest == manifest
    assert result.artifact.object_key == spec.object_key
  end

  defp start_mixer(recording_token) do
    start_supervised!(
      {RoomMixer,
       Map.to_list(@identity) ++
         [
           recording_token: recording_token,
           sample_rate: 8_000,
           channels: 1,
           frame_samples: 2,
           maximum_buffered_timestamps: 2,
           maximum_sink_frames: 8,
           register: false,
           schedule: fn _target, _message, _delay_ms -> make_ref() end
         ]}
    )
  end

  defp subscribe_monitor(mixer) do
    assert {:ok, monitor} =
             RoomMixer.subscribe(mixer,
               id: "monitor-output",
               tenant_id: @identity.tenant_id,
               room_id: @identity.room_id,
               incarnation_id: @identity.incarnation_id,
               recipient_participant_id: "monitor",
               mode: :full_mix,
               subscriber: self()
             )

    monitor
  end

  defp apply_policy(mixer, revision, record_audio?) do
    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["alice", "bob", "monitor"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: record_audio?,
        save_transcripts: true
      }
    }

    Enforcer.apply(mixer, snapshot, 100)
  end

  defp flush_mix(mixer, sequence, timestamp, policy_revision, alice, bob) do
    assert :ok =
             RoomMixer.push(mixer, frame("alice", sequence, timestamp, policy_revision, alice))

    assert :ok = RoomMixer.push(mixer, frame("bob", sequence, timestamp, policy_revision, bob))
    assert {:ok, %{dropped: 0}} = RoomMixer.flush_through(mixer, timestamp)
  end

  defp frame(source, sequence, timestamp, policy_revision, samples) do
    struct!(NormalizedFrame, %{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: "connection-#{source}",
      track_id: "track-#{source}",
      sequence_number: sequence,
      timestamp: timestamp,
      policy_revision: policy_revision,
      sample_rate: 8_000,
      channels: 1,
      payload: encode_samples(samples)
    })
  end

  defp assert_monitor(monitor, expected_samples, policy_revision) do
    assert {:ok, [%MixedFrame{} = frame]} = RoomMixer.take(monitor, 1)
    assert frame.policy_revision == policy_revision
    assert decode_samples(frame.payload) == expected_samples
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
