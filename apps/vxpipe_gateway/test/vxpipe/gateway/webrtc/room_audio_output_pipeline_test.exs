defmodule Vxpipe.Gateway.WebRTC.RoomAudioOutputPipelineTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias Membrane.Opus.Decoder.Native
  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.Gateway.WebRTC.RoomAudioOutputPipeline

  @pipeline_timeout 2_000

  test "encodes aligned mixer PCM as one paced Opus RTP stream" do
    pipeline_id = unique_id("room-output")
    test_process = self()

    send_rtp = fn _peer, "track-output", %Packet{} = packet ->
      send(test_process, {:test_room_rtp, packet})
      :ok
    end

    _supervisor =
      start_supervised!(
        {RoomAudioOutputPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         peer_connection: self(),
         track_id: "track-output",
         subscription_id: "subscription-output",
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         send_rtp: send_rtp}
      )

    assert_receive {:vxpipe_room_audio_output_ready, ^pipeline_id}, @pipeline_timeout
    assert :ok = RoomAudioOutputPipeline.push(pipeline_id, frame(0, 1_000))
    assert :ok = RoomAudioOutputPipeline.push(pipeline_id, frame(960, 2_000))

    assert_receive {:test_room_rtp, %Packet{} = first_packet}, @pipeline_timeout
    assert_receive {:test_room_rtp, %Packet{} = second_packet}, @pipeline_timeout

    assert first_packet.payload_type == 111
    assert first_packet.ssrc == second_packet.ssrc
    assert rem(second_packet.sequence_number - first_packet.sequence_number, 65_536) == 1
    assert rem(second_packet.timestamp - first_packet.timestamp, 4_294_967_296) == 960

    decoder = Native.create(48_000, 1)
    assert byte_size(Native.decode_packet(decoder, first_packet.payload)) == 1_920

    assert_receive {:vxpipe_room_audio_output_sent, ^pipeline_id, 0}, @pipeline_timeout
    assert_receive {:vxpipe_room_audio_output_sent, ^pipeline_id, 960}, @pipeline_timeout
  end

  test "rejects mixer output outside its pinned recipient and format" do
    pipeline_id = unique_id("room-output-invalid")

    _supervisor =
      start_supervised!(
        {RoomAudioOutputPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         peer_connection: self(),
         track_id: "track-output",
         subscription_id: "subscription-output",
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         send_rtp: fn _peer, _track, _packet -> :ok end}
      )

    assert_receive {:vxpipe_room_audio_output_ready, ^pipeline_id}, @pipeline_timeout
    valid = frame(0, 1_000)

    assert {:error, :wrong_participant} =
             RoomAudioOutputPipeline.push(pipeline_id, %{
               valid
               | recipient_participant_id: "part-other"
             })

    assert {:error, :unsupported_audio} =
             RoomAudioOutputPipeline.push(pipeline_id, %{valid | sample_rate: 16_000})
  end

  defp frame(timestamp, sample) do
    %MixedFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      subscription_id: "subscription-output",
      recipient_participant_id: "part-human",
      mode: :mix_minus,
      source_participant_ids: ["part-other"],
      timestamp: timestamp,
      policy_revision: 2,
      sample_rate: 48_000,
      channels: 1,
      payload: :binary.copy(<<sample::little-signed-16>>, 960)
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
