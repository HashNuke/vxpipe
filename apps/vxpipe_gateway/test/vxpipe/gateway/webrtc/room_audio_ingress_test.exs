defmodule Vxpipe.Gateway.WebRTC.RoomAudioIngressTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.Gateway.WebRTC.{ConnectionPeerSupervisor, PCMFrame, RoomAudioIngress}

  test "starts and registers the per-connection ingress through its owning supervisor" do
    connection_id = unique_id("conn-supervised")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment(self(), snapshot(7))

    assert {:ok, ingress} =
             ConnectionPeerSupervisor.start_room_audio_ingress(
               connection_id,
               attachment,
               [
                 tenant_id: "tenant-demo",
                 room_id: "room-demo",
                 incarnation_id: "rinc-demo",
                 participant_id: "part-human"
               ],
               engine: Vxpipe.Gateway.TestRoomAudioEngine,
               pipeline: Vxpipe.Gateway.TestRoomAudioPipeline,
               pipeline_supervisor: Vxpipe.Gateway.TestRoomAudioPipelineSupervisor,
               pipeline_options: [test_observer: self()],
               jitter_latency_ms: 0
             )

    assert_receive {:test_room_audio_pipeline_started, pipeline_id, _pipeline}
    assert :ok = RoomAudioIngress.push(ingress, audio_frame(1, 1_000))
    assert_receive {:test_room_audio_pipeline_push, _pipeline, %AudioFrame{sequence_number: 1}}

    send(ingress, {:vxpipe_audio_pipeline, pipeline_id, pcm_frame(0, <<1::16, 2::16>>)})
    assert_receive {:test_room_audio, %NormalizedFrame{policy_revision: 7}}
  end

  test "tags normalized PCM with the committed policy and preserves sequence across a purge" do
    attachment = attachment(self(), snapshot(4))
    ingress = start_ingress(attachment)

    assert_receive {:test_room_audio_pipeline_started, first_pipeline_id, first_pipeline}
    assert :ok = RoomAudioIngress.push(ingress, audio_frame(1, 1_000))

    assert_receive {:test_room_audio_pipeline_push, ^first_pipeline,
                    %AudioFrame{sequence_number: 1}}

    send(ingress, {:vxpipe_audio_pipeline, first_pipeline_id, pcm_frame(0, <<1::16, 2::16>>)})

    assert_receive {:test_room_audio,
                    %NormalizedFrame{
                      sequence_number: 1,
                      timestamp: 0,
                      policy_revision: 4,
                      payload: <<1::16, 2::16>>
                    }}

    policy_update =
      Task.async(fn -> GenServer.call(ingress, {:vxpipe_apply_media_policy, snapshot(5)}) end)

    assert_receive {:test_room_audio_pipeline_started, second_pipeline_id, second_pipeline}
    refute second_pipeline_id == first_pipeline_id
    assert Task.yield(policy_update, 0) == nil

    send(ingress, {:vxpipe_audio_pipeline_ready, second_pipeline_id})
    assert Task.await(policy_update) == :ok

    assert {:error, :stale_policy_interval} =
             RoomAudioIngress.push(ingress, audio_frame(2, 1_010))

    send(ingress, {:vxpipe_audio_pipeline, first_pipeline_id, pcm_frame(960, <<3::16, 4::16>>)})
    refute_receive {:test_room_audio, %NormalizedFrame{payload: <<3::16, 4::16>>}}

    send(ingress, {:vxpipe_audio_pipeline, second_pipeline_id, pcm_frame(960, <<5::16, 6::16>>)})

    assert_receive {:test_room_audio,
                    %NormalizedFrame{
                      sequence_number: 2,
                      timestamp: 960,
                      policy_revision: 5,
                      payload: <<5::16, 6::16>>
                    }}

    assert :ok = RoomAudioIngress.push(ingress, audio_frame(2, 1_020))

    assert_receive {:test_room_audio_pipeline_push, ^second_pipeline,
                    %AudioFrame{sequence_number: 2}}
  end

  test "does not admit packets until the policy authority installs a snapshot" do
    ingress = start_ingress(attachment(self(), nil), register?: false)

    assert_receive {:test_room_audio_pipeline_started, _pipeline_id, _pipeline}
    assert {:error, :policy_unavailable} = RoomAudioIngress.push(ingress, audio_frame(1, 1_000))
  end

  test "rejects a policy revision when its clean normalizer replacement cannot start" do
    attachment = attachment(self(), snapshot(4))
    ingress = start_ingress(attachment, pipeline_options: [test_fail_generation: 2])

    assert_receive {:test_room_audio_pipeline_started, _pipeline_id, _pipeline}

    assert {:error, :test_pipeline_unavailable} =
             GenServer.call(ingress, {:vxpipe_apply_media_policy, snapshot(5)})

    assert {:error, :pipeline_unavailable} =
             RoomAudioIngress.push(ingress, audio_frame(1, 1_020))
  end

  defp start_ingress(attachment, options \\ []) do
    connection_id = unique_id("conn")

    start_supervised!(
      {RoomAudioIngress,
       connection_id: connection_id,
       attachment: attachment,
       configuration: attachment.configuration,
       tenant_id: "tenant-demo",
       room_id: "room-demo",
       incarnation_id: "rinc-demo",
       participant_id: "part-human",
       owner: self(),
       jitter_latency_ms: 0,
       clock: fn -> 1_010 end,
       engine: Vxpipe.Gateway.TestRoomAudioEngine,
       pipeline: Vxpipe.Gateway.TestRoomAudioPipeline,
       pipeline_supervisor: Vxpipe.Gateway.TestRoomAudioPipelineSupervisor,
       pipeline_options:
         Keyword.merge(
           [test_observer: self()],
           Keyword.get(options, :pipeline_options, [])
         )}
    )
    |> tap(fn ingress ->
      assert :ok = RoomAudioIngress.start_pipeline(ingress)

      if Keyword.get(options, :register?, true) do
        assert {:ok, %Snapshot{}} =
                 Vxpipe.Gateway.TestRoomAudioEngine.register_room_audio_enforcer(
                   attachment,
                   ingress
                 )
      end
    end)
  end

  defp attachment(observer, snapshot) do
    %{
      observer: observer,
      snapshot: snapshot,
      configuration: %{
        clock_origin_ms: 900,
        sample_rate: 48_000,
        channels: 1,
        frame_samples: 960
      }
    }
  end

  defp snapshot(revision) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["part-human"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }
  end

  defp audio_frame(sequence_number, received_at) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "track-a",
      codec: :opus,
      sample_rate: 48_000,
      channels: 2,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      payload: <<1, 2, 3>>,
      received_at: received_at
    }
  end

  defp pcm_frame(timestamp, payload) do
    %PCMFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "track-a",
      timestamp: timestamp,
      sample_rate: 48_000,
      channels: 1,
      payload: payload
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
