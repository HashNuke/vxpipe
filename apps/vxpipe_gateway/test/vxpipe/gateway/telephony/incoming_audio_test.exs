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

  # Speech-to-speech providers ask for their own PCM rate (GPT-Live: 24 kHz). Telephony
  # input must produce any requested rate rather than refusing it.
  test "readiness advertises any mono PCM rate for both carriers" do
    for {codec, source_rate} <- [opus: 16_000, pcmu: 8_000],
        rate <- [8_000, 12_000, 16_000, 22_050, 24_000, 44_100, 48_000] do
      target = %{codec: :linear16, sample_rate: rate, channels: 1}

      assert {:ok, %{codec: :linear16, sample_rate: ^rate, channels: 1}} =
               IncomingAudio.speech_track(
                 %{codec: codec, sample_rate: source_rate, channels: 1},
                 target
               )
    end
  end

  test "Twilio audio reaches 24 kHz with its pitch and contiguous frames" do
    target = %{codec: :linear16, sample_rate: 24_000, channels: 1}
    tone = sine(1_000, 8_000, 320)

    outputs =
      for {offset, samples} <- [
            {0, binary_part(tone, 0, 320)},
            {160, binary_part(tone, 320, 320)}
          ] do
        assert {:ok, pcmu} = Codec.encode(samples)
        frame = %{frame(:pcmu, 8_000, pcmu) | timestamp: offset}
        assert {:ok, normalizer} = IncomingAudio.new_normalizer(frame, target)
        assert {:ok, converted} = IncomingAudio.speech_frame(frame, normalizer)
        assert converted.codec == :linear16
        assert converted.sample_rate == 24_000
        converted
      end

    assert Enum.map(outputs, & &1.timestamp) == [0, 480]
    assert Enum.map(outputs, &byte_size(&1.payload)) == [960, 960]
    payload = Enum.map_join(outputs, & &1.payload)
    # 1 kHz over 40 ms crosses zero about 80 times.
    assert_in_delta zero_crossings(payload), 80, 4
  end

  test "an uneven rate tiles frames exactly without drift" do
    target = %{codec: :linear16, sample_rate: 22_050, channels: 1}
    assert {:ok, pcmu} = Codec.encode(:binary.copy(<<0, 4>>, 160))

    {total, _next} =
      Enum.reduce(0..49, {0, nil}, fn index, {total, expected_timestamp} ->
        frame = %{frame(:pcmu, 8_000, pcmu) | timestamp: index * 160, sequence_number: index}
        assert {:ok, normalizer} = IncomingAudio.new_normalizer(frame, target)
        assert {:ok, converted} = IncomingAudio.speech_frame(frame, normalizer)
        samples = div(byte_size(converted.payload), 2)
        if expected_timestamp, do: assert(converted.timestamp == expected_timestamp)
        {total + samples, converted.timestamp + samples}
      end)

    # One second of 8 kHz input is exactly one second at 22.05 kHz.
    assert total == 22_050
  end

  test "Telnyx Opus decodes natively to 24 kHz and resamples other rates" do
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)
    pcm = :binary.copy(<<1, 0>>, 320)
    assert {:ok, opus} = Membrane.Opus.Encoder.Native.encode_packet(encoder, pcm, 320)

    for {rate, samples} <- [{24_000, 480}, {22_050, 441}] do
      target = %{codec: :linear16, sample_rate: rate, channels: 1}
      frame = %{frame(:opus, 16_000, opus) | timestamp: 0}
      assert {:ok, normalizer} = IncomingAudio.new_normalizer(frame, target)
      assert {:ok, converted} = IncomingAudio.speech_frame(frame, normalizer)
      assert converted.codec == :linear16
      assert converted.sample_rate == rate
      assert converted.timestamp == 0
      assert byte_size(converted.payload) == samples * 2
      assert frame.payload == opus
    end
  end

  defp sine(frequency, rate, samples) do
    for index <- 0..(samples - 1), into: <<>> do
      value = round(8_000 * :math.sin(2 * :math.pi() * frequency * index / rate))
      <<value::little-signed-16>>
    end
  end

  defp zero_crossings(pcm) do
    samples = for <<sample::little-signed-16 <- pcm>>, do: sample

    samples
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [a, b] -> (a < 0 and b >= 0) or (a >= 0 and b < 0) end)
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
