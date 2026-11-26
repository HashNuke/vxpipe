defmodule Vxpipe.Artifacts.RecordingPipelineTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.{RecordingWriter, TestObjectStore}
  alias Vxpipe.CallEngine.Media.{EgressAcceptedFrame, MixedFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Recording.EgressHandoff
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

    if is_nil(Process.whereis(Vxpipe.CallEngine.ReadinessWatchRegistry)) do
      start_supervised!(
        {Registry, keys: :duplicate, name: Vxpipe.CallEngine.ReadinessWatchRegistry}
      )
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
             targets: [:room_track],
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
             targets: [{:individual_tracks, ["alice"]}],
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

    assert :ok =
             RoomRecording.prepare_tracks(
               recording,
               [{:individual_track, "alice", "connection-alice", "track-alice"}],
               0
             )

    assert_receive {:test_object_store_opened, _task, spec}
    assert spec.kind == :participant_track
    assert spec.participant_id == "alice"
    assert {:ok, ready, :ready} = RoomRecording.readiness(recording)

    first_alice = [1_000, 2_000]
    flush_mix(mixer, 1, 0, 0, [1_000, 2_000], [3_000, -5_000])
    assert_monitor(monitor, [4_000, -3_000], 0)

    assert_receive {:test_object_store_write, first_task, first_reference, first_chunk}
    assert first_chunk.sequence == 0
    assert first_chunk.offset_samples == 0
    assert decode_samples(first_chunk.payload) == first_alice

    :ok = apply_policy(mixer, 1, false)
    denied_mix = [1_200, 1_400]
    flush_mix(mixer, 2, 2, 1, [500, 600], [700, 800])
    assert_monitor(monitor, denied_mix, 0)
    refute_receive {:test_object_store_write, _task, _reference, _chunk}

    :ok = apply_policy(mixer, 2, true)

    assert :ok =
             RoomRecording.prepare_tracks(
               recording,
               [{:individual_track, "alice", "connection-alice", "track-alice"}],
               2
             )

    second_alice = [10, 20]
    flush_alice(mixer, 3, 4, 2, second_alice)
    assert_monitor(monitor, second_alice, 0)

    rejected_alice = [50, 60]
    flush_alice(mixer, 4, 6, 2, rejected_alice)
    assert_monitor(monitor, rejected_alice, 0)

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
    assert decode_samples(second_chunk.payload) == second_alice

    final_alice = [100, 200]
    flush_alice(mixer, 5, 8, 2, final_alice)
    assert_monitor(monitor, final_alice, 0)

    _state = :sys.get_state(recording)

    assert %{accepted_chunks: 3, rejected_chunks: 1} = RoomRecording.stats(recording)

    send(second_task, {:test_object_store_continue, second_reference})

    assert_receive {:test_object_store_write, third_task, third_reference, third_chunk}
    assert third_chunk.sequence == 3
    assert third_chunk.offset_samples == 8
    assert decode_samples(third_chunk.payload) == final_alice
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

  test "records room, reconnected caller and receptionist agent tracks with no mix" do
    token = make_ref()
    mixer = start_composite_mixer(token)
    :ok = apply_composite_policy(mixer, 0, true)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(@identity) ++
           [
             mixer: mixer,
             recording_token: token,
             targets: [:room_track, {:individual_tracks, ["caller", "receptionist"]}],
             participant_keys: %{"caller" => "caller", "receptionist" => "receptionist"},
             writer:
               {RecordingWriter,
                [
                  object_store: TestObjectStore,
                  object_store_options: [observer: self(), report_artifact: true],
                  maximum_pending_chunks: 8,
                  drain_timeout_ms: 1_000,
                  observer: self()
                ]},
             maximum_pull_frames: 4
           ]}
      )

    caller_first = {:individual_track, "caller", "connection-caller", "track-caller"}
    caller_second = {:individual_track, "caller", "connection-caller-2", "track-caller-2"}
    agent = {:individual_track, "receptionist", "receptionist", "agent-egress"}

    assert :ok =
             RoomRecording.prepare_tracks(
               recording,
               [caller_first, caller_second, agent, :room_track],
               0
             )

    specs_by_writer = collect_opened_specs(4, %{})

    assert map_size(specs_by_writer) == 4
    assert Enum.all?(specs_by_writer, fn {_pid, spec} -> spec.kind != :full_mix end)

    assert ["caller", "caller-1", "receptionist", "room"] ==
             specs_by_writer
             |> Map.values()
             |> Enum.map(&artifact_name/1)
             |> Enum.sort()

    {:ok, room_handoff} = RoomMixer.open_recording_egress(mixer, "connection-caller", "caller")

    {:ok, agent_handoff} =
      RoomMixer.open_recording_egress(mixer, "connection-caller-2", "caller")

    opening_samples = [4_001, 4_002]
    wait_samples = [4_003, 4_004]
    caller_samples = [1_001, 1_002]
    caller_reconnect_samples = [2_001, 2_002]
    agent_samples = [3_001, 3_002]

    assert :ok =
             EgressHandoff.offer(
               room_handoff,
               egress_frame("caller", "connection-caller", :room, opening_samples)
             )

    assert :ok =
             EgressHandoff.offer(
               agent_handoff,
               egress_frame("receptionist", "connection-caller-2", :participant, agent_samples)
             )

    assert :ok =
             RoomMixer.push(
               mixer,
               ingress_frame(
                 "caller",
                 "connection-caller",
                 "track-caller",
                 1,
                 0,
                 0,
                 caller_samples
               )
             )

    assert {:ok, %{delivered: delivered}} = RoomMixer.flush_through(mixer, 0)
    assert delivered == 3

    first_writes = collect_writes(3, %{})

    assert decode_samples(Map.fetch!(first_writes, "room").payload) == opening_samples
    assert Map.fetch!(first_writes, "room").offset_samples == 0
    assert decode_samples(Map.fetch!(first_writes, "caller").payload) == caller_samples
    assert Map.fetch!(first_writes, "caller").offset_samples == 0
    assert decode_samples(Map.fetch!(first_writes, "receptionist").payload) == agent_samples
    assert Map.fetch!(first_writes, "receptionist").offset_samples == 0

    assert :ok =
             EgressHandoff.offer(
               room_handoff,
               egress_frame("caller", "connection-caller", :room, wait_samples)
             )

    assert :ok =
             RoomMixer.push(
               mixer,
               ingress_frame(
                 "caller",
                 "connection-caller-2",
                 "track-caller-2",
                 1,
                 2,
                 0,
                 caller_reconnect_samples
               )
             )

    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 2)

    wait_writes = collect_writes(2, %{})
    assert decode_samples(Map.fetch!(wait_writes, "caller-1").payload) == caller_reconnect_samples
    assert Map.fetch!(wait_writes, "caller-1").offset_samples == 2
    assert decode_samples(Map.fetch!(wait_writes, "room").payload) == wait_samples
    assert Map.fetch!(wait_writes, "room").offset_samples == 2

    assert %{accepted_chunks: 5, rejected_chunks: 0, streams: 4} =
             RoomRecording.stats(recording)

    recording_monitor = Process.monitor(recording)
    GenServer.stop(recording, :normal)
    assert_receive {:DOWN, ^recording_monitor, :process, ^recording, :normal}

    manifests = collect_manifests(4, [])
    assert length(manifests) == 4

    assert ["caller", "caller-1", "receptionist", "room"] ==
             manifests |> Enum.map(&artifact_name/1) |> Enum.sort()

    assert Enum.all?(manifests, &(&1.kind != :full_mix))

    by_name = Map.new(manifests, &{artifact_name(&1), &1})

    assert %{reconnection: 0, participant_key: "caller"} = by_name["caller"]
    assert %{reconnection: 1, participant_key: "caller"} = by_name["caller-1"]
    assert %{reconnection: 0, participant_key: "receptionist"} = by_name["receptionist"]
    assert %{kind: :room_track} = by_name["room"]

    assert by_name["caller"].started_offset_samples == 0
    assert by_name["caller-1"].started_offset_samples == 2
    assert by_name["receptionist"].started_offset_samples == 0
    assert by_name["room"].started_offset_samples == 0
    assert by_name["room"].ended_offset_samples == 4
    assert by_name["room"].sample_count == 4
    assert by_name["room"].accepted_chunks == 2
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

  defp flush_alice(mixer, sequence, timestamp, policy_revision, alice) do
    assert :ok =
             RoomMixer.push(mixer, frame("alice", sequence, timestamp, policy_revision, alice))

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

  defp start_composite_mixer(recording_token) do
    start_supervised!(
      {RoomMixer,
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
           register: false,
           schedule: fn _target, _message, _delay_ms -> make_ref() end
         ]}
    )
  end

  defp apply_composite_policy(mixer, revision, record_audio?) do
    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["caller", "receptionist"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: record_audio?,
        save_transcripts: true
      }
    }

    Enforcer.apply(mixer, snapshot, 100)
  end

  defp ingress_frame(source, connection, track, sequence, timestamp, policy_revision, samples) do
    struct!(NormalizedFrame, %{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection,
      track_id: track,
      sequence_number: sequence,
      timestamp: timestamp,
      policy_revision: policy_revision,
      sample_rate: 8_000,
      channels: 1,
      origin: :participant,
      payload: encode_samples(samples)
    })
  end

  defp egress_frame(source, connection, origin, samples) do
    %EgressAcceptedFrame{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection,
      sample_rate: 8_000,
      channels: 1,
      origin: origin,
      payload: encode_samples(samples)
    }
  end

  defp collect_opened_specs(0, acc), do: acc

  defp collect_opened_specs(remaining, acc) do
    assert_receive {:test_object_store_opened, writer_pid, spec}, 1_000
    assert spec.kind != :full_mix
    collect_opened_specs(remaining - 1, Map.put(acc, writer_pid, spec))
  end

  defp collect_writes(0, acc), do: acc

  defp collect_writes(remaining, acc) do
    assert_receive {:test_artifact_write, task, reference, spec, chunk}, 1_000
    send(task, {:test_object_store_continue, reference})
    collect_writes(remaining - 1, Map.put(acc, artifact_name(spec), chunk))
  end

  defp artifact_name(%{kind: :room_track}), do: "room"
  defp artifact_name(%{participant_key: key, reconnection: 0}), do: key
  defp artifact_name(%{participant_key: key, reconnection: count}), do: "#{key}-#{count}"

  defp collect_manifests(0, acc), do: acc

  defp collect_manifests(remaining, acc) do
    assert_receive {:test_object_store_completed, _task, manifest}, 1_000
    collect_manifests(remaining - 1, [manifest | acc])
  end
end
