defmodule Vxpipe.Gateway.Media.RoomMediaReadinessTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{ConnectionAttachment, RoomAudioHandle, RoomMixer}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.Gateway.Media.RoomAudioEgress

  test "collects the real mixer binding and waits for matching output policy" do
    identity = [tenant_id: "tenant-media", room_id: "room-media", incarnation_id: "inc-media"]
    mixer = start_mixer(identity)
    assert :ok = Enforcer.apply(mixer, snapshot(4), 1_000)
    egress = start_egress(identity, mixer)
    assert :ok = RoomAudioEgress.activate(egress)
    assert :ok = Enforcer.apply(egress, snapshot(4), 1_000)
    assert_receive {:test_room_audio_output_pipeline_started, first_id, _pipeline, ^egress}
    send(egress, {:vxpipe_room_audio_output_ready, first_id})

    assert {:ok, [resource, subscription] = resources} =
             RoomAudioEgress.readiness_resources(egress)

    assert subscription.instance == mixer

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: "inc-media",
         attempt_id: "transfer-media",
         resources: resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    changed = put_in(snapshot(5).effective.audio_routes, %{})
    assert :ok = Enforcer.apply(mixer, changed, 1_000)
    assert {:ok, ^resource, :preparing} = RoomAudioEgress.readiness(egress)

    tasks = start_supervised!({Task.Supervisor, name: {:global, {__MODULE__, make_ref()}}})
    update = Task.Supervisor.async_nolink(tasks, fn -> Enforcer.apply(egress, changed, 1_000) end)
    assert_receive {:test_room_audio_output_pipeline_started, next_id, _pipeline, ^egress}
    send(egress, {:vxpipe_room_audio_output_ready, first_id})
    assert {:ok, replacement, :preparing} = RoomAudioEgress.readiness(egress)
    send(egress, {:vxpipe_room_audio_output_ready, next_id})
    assert :ok = Task.await(update)
    assert {:ok, ^replacement, :ready} = RoomAudioEgress.readiness(egress)
    refute replacement.generation == resource.generation
    assert replacement.configuration == resource.configuration

    assert {:ok, [^replacement, updated_subscription]} =
             RoomAudioEgress.readiness_resources(egress)

    assert updated_subscription.generation == subscription.generation
    assert updated_subscription.policy_interval == 5

    assert :ok = stop_supervised({RoomMixer, "inc-media"})
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000
    assert {:error, :unavailable} = RoomAudioEgress.readiness(egress)
  end

  defp start_mixer(identity) do
    start_supervised!(
      {RoomMixer,
       identity ++
         [
           sample_rate: 48_000,
           channels: 1,
           frame_samples: 960,
           maximum_buffered_timestamps: 4,
           maximum_sink_frames: 4,
           register: false
         ]}
    )
  end

  defp start_egress(identity, mixer) do
    attachment = %ConnectionAttachment{
      room_monitor: Process.monitor(mixer),
      media_ingress: nil,
      room_audio_output_mode: :mix_minus,
      room_audio: %RoomAudioHandle{
        mixer: mixer,
        media_policy_authority: self(),
        configuration: %{}
      }
    }

    start_supervised!(
      {RoomAudioEgress,
       identity ++
         [
           participant_id: "human",
           connection_id: "media-#{System.unique_integer([:positive])}",
           attachment: attachment,
           owner: self(),
           pipeline: Vxpipe.Gateway.TestRoomAudioOutputPipeline,
           pipeline_supervisor: Vxpipe.Gateway.TestRoomAudioOutputPipelineSupervisor,
           pipeline_options: [test_observer: self()]
         ]}
    )
  end

  defp snapshot(revision) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["human", "caller"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }
  end
end
