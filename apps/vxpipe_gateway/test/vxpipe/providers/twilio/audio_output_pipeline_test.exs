defmodule Vxpipe.Providers.Twilio.AudioOutputPipelineTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Gateway.Media.PlaybackFrame
  alias Vxpipe.Providers.Twilio.AudioOutputPipeline

  @pipeline_timeout 2_000

  test "encodes one acknowledged PCM playout frame as paced Twilio PCMU media" do
    pipeline_id = start_pipeline()
    frame = frame(0, 0, 0)

    assert :ok = AudioOutputPipeline.push(pipeline_id, frame)
    assert_receive {:vxpipe_twilio_socket_send, message}, @pipeline_timeout
    assert media_payload(message) == :binary.copy(<<0xFF>>, 160)
    assert_receive {:vxpipe_audio_output_pipeline_sent, ^pipeline_id, 0}, @pipeline_timeout
  end

  test "rejects malformed and out-of-order coordinator frames" do
    pipeline_id = start_pipeline()
    first = frame(0, 0, 0)

    assert {:error, :unsupported_audio} =
             AudioOutputPipeline.push(pipeline_id, %{first | payload: <<1, 2>>})

    assert {:error, :unaligned_frame} =
             AudioOutputPipeline.push(pipeline_id, %{first | timestamp: 1})

    assert :ok = AudioOutputPipeline.push(pipeline_id, first)
    assert {:error, :stale_sequence} = AudioOutputPipeline.push(pipeline_id, first)
  end

  defp start_pipeline do
    pipeline_id = unique_id("twilio-audio-output")

    _supervisor =
      start_supervised!(
        {AudioOutputPipeline,
         pipeline_id: pipeline_id,
         owner: self(),
         socket_owner: self(),
         stream_id: "MZ00000000000000000000000000000000",
         connection_id: "conn-demo",
         tenant_id: "tenant-demo",
         room_id: "room-demo",
         incarnation_id: "rinc-demo",
         participant_id: "part-human"}
      )

    assert_receive {:vxpipe_audio_output_pipeline_ready, ^pipeline_id}, @pipeline_timeout
    pipeline_id
  end

  defp media_payload(message) do
    assert %{
             "event" => "media",
             "streamSid" => "MZ00000000000000000000000000000000",
             "media" => %{"payload" => encoded}
           } = JSON.decode!(message)

    assert {:ok, packet} = Base.decode64(encoded)
    packet
  end

  defp frame(sequence_number, timestamp, sample) do
    %PlaybackFrame{
      sequence_number: sequence_number,
      timestamp: timestamp,
      sample_rate: 48_000,
      payload: :binary.copy(<<sample::little-signed-16>>, 960)
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
