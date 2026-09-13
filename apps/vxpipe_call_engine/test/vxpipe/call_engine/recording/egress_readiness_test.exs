defmodule Vxpipe.CallEngine.Recording.EgressReadinessTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Recording.EgressReadiness
  alias Vxpipe.CallEngine.{RoomMixer, TestRecordingOutput}

  @identity %{
    tenant_id: "tenant-recording-readiness",
    room_id: "room-recording-readiness",
    incarnation_id: "incarnation-recording-readiness",
    participant_id: "caller",
    connection_id: "listener-connection"
  }

  setup context do
    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(Map.take(@identity, [:tenant_id, :room_id, :incarnation_id])) ++
           [
             recording_token: make_ref(),
             register: false,
             sample_rate: Map.get(context, :mixer_sample_rate, 48_000),
             channels: 1,
             frame_samples: Map.get(context, :mixer_frame_samples, 960),
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4
           ]}
      )

    policy = policy(0)
    :ok = Enforcer.apply(mixer, policy, 1_000)
    native = start_supervised!({TestRecordingOutput, observer: self()})
    assert {:ok, resource, :ready} = TestRecordingOutput.readiness(native)
    %{mixer: mixer, native: native, resource: resource, policy: policy}
  end

  test "requires the bound tap and preserves codec generation and recording interval", context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, mixer, policy)
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)
    assert {:ok, binding} = EgressReadiness.prepare(resource, @identity, mixer, policy)
    assert binding.resource.generation == resource.generation
    assert binding.track_id == "agent-egress"
    assert binding.connection_id == @identity.connection_id
    assert binding.status == :ready
    assert {:ok, ^binding} = EgressReadiness.prepare(resource, @identity, mixer, policy)
    assert {:ok, observed, :ready} = EgressReadiness.readiness_binding(binding.resource)
    assert observed == binding.resource

    :ok = Enforcer.apply(mixer, policy(1, transcript_routes: %{}), 1_000)
    assert {:ok, ^observed, :ready} = EgressReadiness.readiness_binding(binding.resource)
  end

  @tag mixer_sample_rate: 8_000
  test "rejects a tap whose mixer format cannot accept the native output PCM", context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)
    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, mixer, policy)
  end

  test "rejects mismatched identity, mixer, receiving connection and policy", context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)

    for key <- Map.keys(@identity) do
      identity = Map.put(@identity, key, "foreign")
      assert {:error, :unavailable} = EgressReadiness.prepare(resource, identity, mixer, policy)
    end

    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, self(), policy)
    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, mixer, policy(1))
    assert {:ok, foreign} = RoomMixer.open_recording_egress(mixer, "another-connection")
    :ok = TestRecordingOutput.bind(native, foreign)
    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, mixer, policy)
  end

  @tag mixer_frame_samples: 480
  test "rejects a tap whose recording frame size differs from native output", context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)
    assert {:error, :unavailable} = EgressReadiness.prepare(resource, @identity, mixer, policy)
  end

  test "rechecks the native binding after a dependency observation without blocking its owner",
       context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:ok, first} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    assert {:ok, replacement} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, first)
    :ok = TestRecordingOutput.pause_binding(native)
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        EgressReadiness.prepare(resource, @identity, mixer, policy)
      end)

    assert_receive {:recording_binding_paused, worker}
    assert {:ok, ^resource, :ready} = TestRecordingOutput.readiness(native)
    :ok = TestRecordingOutput.bind(native, replacement)
    send(worker, :continue)
    assert {:error, :unavailable} = Task.await(task)
    assert {:ok, _binding} = EgressReadiness.prepare(resource, @identity, mixer, policy)
  end

  test "replacement of a tap invalidates the collected binding without restarting the codec",
       context do
    %{native: native, mixer: mixer, resource: resource, policy: policy} = context
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)
    assert {:ok, binding} = EgressReadiness.prepare(resource, @identity, mixer, policy)

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: @identity.incarnation_id,
         attempt_id: "recording-tap",
         resources: [binding.resource],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, replacement} = RoomMixer.open_recording_egress(mixer, @identity.connection_id)
    :ok = TestRecordingOutput.bind(native, replacement)
    :ok = Collector.refresh(collector)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000
    assert {:ok, ^resource, :ready} = TestRecordingOutput.readiness(native)
  end

  defp policy(revision, overrides \\ []) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["caller", "agent"]),
      effective:
        struct!(
          Effective,
          Keyword.merge(
            [
              audio_routes: :unrestricted,
              transcript_routes: :unrestricted,
              record_audio: true,
              save_transcripts: true
            ],
            overrides
          )
        )
    }
  end
end
