defmodule Vxpipe.Gateway.Telephony.Twilio.AudioIngressPipelineTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Media.PCMFrame
  alias Vxpipe.Gateway.Telephony.Twilio.AudioIngressPipeline

  @pipeline_timeout 2_000

  test "decodes Twilio PCMU into room-aligned 48 kHz mono PCM without FFmpeg" do
    pipeline_id = start_pipeline()

    assert :ok =
             AudioIngressPipeline.push(
               pipeline_id,
               frame(4, 60, 1_043, :binary.copy(<<0xFF>>, 160))
             )

    assert_receive {:vxpipe_audio_pipeline, ^pipeline_id,
                    %PCMFrame{
                      track_id: "stream-1",
                      timestamp: 1_920,
                      sample_rate: 48_000,
                      channels: 1,
                      payload: pcm
                    }},
                   @pipeline_timeout

    assert pcm == :binary.copy(<<0::little-signed-16>>, 960)
  end

  test "rejects another identity, format, track, or stale provider chunk" do
    pipeline_id = start_pipeline()
    input = frame(4, 60, 1_043, :binary.copy(<<0xFF>>, 160))

    for {field, value, reason} <- [
          {:connection_id, "conn-other", :wrong_connection},
          {:tenant_id, "tenant-other", :wrong_tenant},
          {:room_id, "room-other", :wrong_room},
          {:incarnation_id, "rinc-other", :wrong_incarnation},
          {:participant_id, "part-other", :wrong_participant},
          {:track_id, "stream-other", :wrong_track},
          {:codec, :opus, :unsupported_audio},
          {:sample_rate, 48_000, :unsupported_audio},
          {:channels, 2, :unsupported_audio}
        ] do
      assert {:error, ^reason} =
               AudioIngressPipeline.push(pipeline_id, Map.put(input, field, value))
    end

    assert :ok = AudioIngressPipeline.push(pipeline_id, input)

    assert {:error, :stale_sequence} =
             AudioIngressPipeline.push(pipeline_id, %{input | timestamp: 80})

    assert {:error, :stale_timestamp} =
             AudioIngressPipeline.push(pipeline_id, %{
               input
               | sequence_number: 5,
                 timestamp: 40
             })
  end

  defp start_pipeline do
    pipeline_id = unique_id("twilio-audio-ingress")

    _supervisor =
      start_supervised!(
        {AudioIngressPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human",
         connection_id: "conn-demo",
         track_id: "stream-1",
         clock_origin_ms: 1_000}
      )

    assert_receive {:vxpipe_audio_pipeline_ready, ^pipeline_id}, @pipeline_timeout
    pipeline_id
  end

  defp frame(sequence_number, timestamp, received_at, payload) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "stream-1",
      codec: :pcmu,
      sample_rate: 8_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: timestamp,
      payload: payload,
      received_at: received_at
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
