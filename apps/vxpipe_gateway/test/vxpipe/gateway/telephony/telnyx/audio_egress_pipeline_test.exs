defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioEgressPipelineTest do
  use ExUnit.Case, async: true

  alias Membrane.Opus.Decoder.Native
  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.Gateway.Telephony.Telnyx.AudioEgressPipeline

  @pipeline_timeout 2_000

  test "encodes authorized room PCM as paced Telnyx media envelopes" do
    pipeline_id = start_pipeline()

    assert :ok = AudioEgressPipeline.push(pipeline_id, frame(0, 1_000))
    assert :ok = AudioEgressPipeline.push(pipeline_id, frame(960, 2_000))

    assert_receive {:vxpipe_telnyx_socket_send, first_message}, @pipeline_timeout
    assert_receive {:vxpipe_telnyx_socket_send, second_message}, @pipeline_timeout

    first_packet = media_payload(first_message)
    second_packet = media_payload(second_message)

    decoder = Native.create(48_000, 1)
    assert byte_size(Native.decode_packet(decoder, first_packet)) == 1_920
    assert byte_size(Native.decode_packet(decoder, second_packet)) == 1_920

    assert_receive {:vxpipe_telnyx_audio_egress_sent, ^pipeline_id, 0}, @pipeline_timeout
    assert_receive {:vxpipe_telnyx_audio_egress_sent, ^pipeline_id, 960}, @pipeline_timeout
  end

  test "rejects mixer output outside the pinned subscription and room format" do
    pipeline_id = start_pipeline()
    valid = frame(0, 1_000)

    for {field, value, reason} <- [
          {:tenant_id, "tenant-other", :wrong_tenant},
          {:room_id, "room-other", :wrong_room},
          {:incarnation_id, "rinc-other", :wrong_incarnation},
          {:subscription_id, "subscription-other", :wrong_subscription},
          {:recipient_participant_id, "part-other", :wrong_participant},
          {:mode, :individual_track, :unsupported_mode},
          {:sample_rate, 16_000, :unsupported_audio},
          {:channels, 2, :unsupported_audio},
          {:payload, <<1, 2>>, :unsupported_audio},
          {:timestamp, 1, :unaligned_timestamp}
        ] do
      assert {:error, ^reason} =
               AudioEgressPipeline.push(pipeline_id, Map.put(valid, field, value))
    end
  end

  defp start_pipeline do
    pipeline_id = unique_id("telnyx-audio-egress")

    _supervisor =
      start_supervised!(
        {AudioEgressPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         socket_owner: self(),
         subscription_id: "subscription-output",
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human"}
      )

    assert_receive {:vxpipe_telnyx_audio_egress_ready, ^pipeline_id}, @pipeline_timeout
    pipeline_id
  end

  defp media_payload(message) do
    assert %{"event" => "media", "media" => %{"payload" => encoded}} = JSON.decode!(message)
    assert {:ok, packet} = Base.decode64(encoded)
    packet
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
