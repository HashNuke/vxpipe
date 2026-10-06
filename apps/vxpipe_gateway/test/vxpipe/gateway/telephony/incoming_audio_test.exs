defmodule Vxpipe.Gateway.Telephony.IncomingAudioTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Telephony.IncomingAudio
  alias Vxpipe.Providers.Twilio.PCMU.Codec

  @target %{codec: :linear16, sample_rate: 16_000, channels: 1}

  test "early private destination packets drop while their input routes are unallocated" do
    attachment = %ConnectionAttachment{
      room_monitor: make_ref(),
      media_ingress: nil,
      admission: :transfer_preparation,
      transfer_attempt_id: "private-attempt"
    }

    for packet <- [frame(:pcmu, 8_000, <<255>>), frame(:opus, 16_000, <<0>>)] do
      assert {:drop, nil} = IncomingAudio.deliver(__MODULE__, attachment, nil, packet, nil, nil)

      assert {:unavailable, nil} =
               IncomingAudio.deliver(
                 __MODULE__,
                 %{attachment | admission: :main},
                 nil,
                 packet,
                 nil,
                 nil
               )
    end
  end

  test "readiness advertises normalized PCM for Telnyx Opus and Twilio μ-law" do
    assert {:ok, %{codec: :linear16, sample_rate: 16_000, channels: 1}} =
             IncomingAudio.speech_track(
               %{codec: :opus, sample_rate: 16_000, channels: 1},
               @target
             )

    assert {:ok, %{codec: :linear16, sample_rate: 16_000, channels: 1}} =
             IncomingAudio.speech_track(%{codec: :pcmu, sample_rate: 8_000, channels: 1}, @target)

    assert {:error, :unsupported_audio} =
             IncomingAudio.speech_track(
               %{codec: :opus, sample_rate: 16_000, channels: 2},
               @target
             )
  end

  test "Twilio audio becomes 16 kHz PCM with sample and timestamp continuity" do
    pcm = <<0::little-signed-16, 1000::little-signed-16, 2000::little-signed-16>>
    assert {:ok, pcmu} = Codec.encode(pcm)
    frame = frame(:pcmu, 8_000, pcmu)
    assert {:ok, normalizer} = IncomingAudio.new_normalizer(frame, @target)
    assert {:ok, converted} = IncomingAudio.speech_frame(frame, normalizer)
    assert converted.codec == :linear16
    assert converted.sample_rate == 16_000
    assert converted.timestamp == frame.timestamp * 2
    assert byte_size(converted.payload) == byte_size(pcm) * 2
  end

  test "Telnyx Opus becomes mono 16 kHz PCM without changing the room packet" do
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)
    pcm = :binary.copy(<<1, 0>>, 320)
    assert {:ok, opus} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 320)
    frame = frame(:opus, 16_000, opus)
    assert {:ok, normalizer} = IncomingAudio.new_normalizer(frame, @target)
    assert {:ok, converted} = IncomingAudio.speech_frame(frame, normalizer)
    assert converted.codec == :linear16
    assert converted.sample_rate == 16_000
    assert converted.timestamp == frame.timestamp
    assert byte_size(converted.payload) == byte_size(pcm)
    assert frame.payload == opus
  end

  defp frame(codec, sample_rate, payload) do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller",
      connection_id: "connection",
      track_id: "track",
      codec: codec,
      sample_rate: sample_rate,
      channels: 1,
      sequence_number: 1,
      timestamp: 160,
      payload: payload,
      received_at: System.monotonic_time(:millisecond)
    }
  end
end
