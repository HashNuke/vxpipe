defmodule Vxpipe.Gateway.WebRTC.SpeechInputTest do
  use ExUnit.Case, async: true

  alias Membrane.Opus.Encoder.Native, as: OpusEncoder
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.CapabilityTree
  alias Vxpipe.Gateway.WebRTC.{OpusDecoder, SpeechInput}
  alias Vxpipe.Gateway.WebRTC.OpusEncoder, as: GatewayOpusEncoder

  @track %{track_id: "track-input", codec: :opus, sample_rate: 48_000, channels: 2}

  test "decodes and downmixes stereo Opus for a mono linear16 provider" do
    payload = opus_packet(2)
    assert {:ok, output, input} = SpeechInput.configure(@track, target(:linear16))

    assert output == %{
             track_id: "track-input",
             codec: :linear16,
             sample_rate: 48_000,
             channels: 1
           }

    assert {:ok, reference_decoder} = OpusDecoder.new(48_000)
    assert {:ok, expected} = OpusDecoder.decode(reference_decoder, payload)

    assert {:ok,
            %AudioFrame{
              codec: :linear16,
              sample_rate: 48_000,
              channels: 1,
              payload: ^expected
            }} = SpeechInput.frame(frame(payload), input)
  end

  test "normalizes stereo and mono packets for a mono Opus provider" do
    stereo = opus_packet(2)
    mono = opus_packet(1)
    assert {:ok, output, input} = SpeechInput.configure(@track, target(:opus))
    assert output == %{track_id: "track-input", codec: :opus, sample_rate: 48_000, channels: 1}

    assert {:ok, %AudioFrame{channels: 1, payload: normalized}} =
             SpeechInput.frame(frame(stereo), input)

    assert <<_configuration::5, 0::1, _frame_code::2, _rest::binary>> = normalized
    assert {:ok, decoder} = OpusDecoder.new(48_000)
    assert {:ok, decoded} = OpusDecoder.decode(decoder, normalized)
    assert is_binary(decoded)
    assert byte_size(decoded) == 1_920

    assert {:ok, %AudioFrame{channels: 1, payload: normalized_mono}} =
             SpeechInput.frame(frame(mono), input)

    assert {:ok, 1} = Vxpipe.Gateway.WebRTC.OpusInput.packet_channels(normalized_mono)
  end

  test "supports mono and stereo packet transitions with one prepared input" do
    assert {:ok, _output, input} = SpeechInput.configure(@track, target(:linear16))

    for channels <- [1, 2, 1] do
      assert {:ok, %AudioFrame{channels: 1, payload: pcm}} =
               SpeechInput.frame(frame(opus_packet(channels)), input)

      assert byte_size(pcm) == 1_920
    end
  end

  test "preserves one decoder history across mono and stereo packet transitions" do
    packets = opus_transition_packets()
    assert {:ok, reference_decoder} = OpusDecoder.new(48_000)
    assert {:ok, _output, input} = SpeechInput.configure(@track, target(:linear16))

    {actual, expected} =
      Enum.map_reduce(packets, [], fn payload, expected ->
        assert {:ok, %AudioFrame{payload: actual}} = SpeechInput.frame(frame(payload), input)
        assert {:ok, reference} = OpusDecoder.decode(reference_decoder, payload)
        {actual, [reference | expected]}
      end)

    assert actual == Enum.reverse(expected)
  end

  test "encodes every packet through one mono Opus output history" do
    packets = opus_transition_packets()
    assert {:ok, input_decoder} = OpusDecoder.new(48_000)
    assert {:ok, output_encoder} = GatewayOpusEncoder.new([])
    assert {:ok, _output, input} = SpeechInput.configure(@track, target(:opus))

    for payload <- packets do
      assert {:ok, mono} = OpusDecoder.decode(input_decoder, payload)

      assert {:ok, expected} =
               GatewayOpusEncoder.encode(output_encoder, mono, div(byte_size(mono), 2))

      assert {:ok, %AudioFrame{payload: ^expected}} = SpeechInput.frame(frame(payload), input)
    end
  end

  test "normalizes packet channels when negotiated Opus metadata already matches the provider" do
    mono_track = %{@track | channels: 1}
    stereo = opus_packet(2)

    assert {:ok, ^mono_track, input} = SpeechInput.configure(mono_track, target(:opus))

    assert {:ok, %AudioFrame{channels: 1, payload: normalized}} =
             SpeechInput.frame(frame(stereo), input)

    assert {:ok, 1} = Vxpipe.Gateway.WebRTC.OpusInput.packet_channels(normalized)
  end

  test "classifies an invalid Opus payload without crashing the owning process" do
    assert {:ok, _output, input} = SpeechInput.configure(@track, target(:linear16))
    assert {:error, :invalid_packet} = SpeechInput.frame(frame(<<255>>), input)
  end

  test "prepares against the media format published by a real room ingress" do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    identity = [
      tenant_id: "tenant-#{suffix}",
      room_id: "room-#{suffix}",
      incarnation_id: "rinc-#{suffix}",
      participant_id: "part-#{suffix}",
      connection_id: "conn-#{suffix}"
    ]

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             speech_scope: CapabilityTree.scope(tree),
             provider: {MorseSession, []}
           ]}
      )

    assert_receive {:vxpipe_stt_signal, ^capability, _, %{kind: :connected}}, 1_000

    ingress =
      start_supervised!(
        {Ingress,
         identity ++
           [
             capability: capability,
             maximum_age_ms: 1_000,
             maximum_bytes: 65_536,
             maximum_frames: 20,
             maximum_consecutive_overflows: 3
           ]}
      )

    attachment = %ConnectionAttachment{room_monitor: make_ref(), media_ingress: ingress}

    assert {:ok, %{track_id: "track-input", codec: :linear16, sample_rate: 16_000, channels: 1},
            %{ingress: ^ingress}} = SpeechInput.prepare(attachment, @track, nil)
  end

  defp target(codec), do: %{codec: codec, sample_rate: 48_000, channels: 1}

  defp frame(payload) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      connection_id: "conn-demo",
      track_id: "track-input",
      codec: :opus,
      sample_rate: 48_000,
      channels: 2,
      sequence_number: 1,
      timestamp: 960,
      payload: payload,
      received_at: 1_000
    }
  end

  defp opus_packet(channels) do
    encoder = OpusEncoder.create(48_000, channels, 2_048, 64_000, 3_001)

    pcm =
      for sample <- 0..959, channel <- 1..channels, into: <<>> do
        frequency = if channel == 1, do: 440, else: 660
        value = round(:math.sin(2 * :math.pi() * frequency * sample / 48_000) * 16_000)
        <<value::little-signed-16>>
      end

    assert {:ok, payload} = OpusEncoder.encode_packet(encoder, pcm, 960)
    payload
  end

  defp opus_transition_packets do
    encoders = %{
      1 => OpusEncoder.create(48_000, 1, 2_048, 64_000, 3_001),
      2 => OpusEncoder.create(48_000, 2, 2_048, 64_000, 3_001)
    }

    [1, 1, 2, 2, 1, 1]
    |> Enum.with_index()
    |> Enum.map(fn {channels, packet_index} ->
      pcm =
        for sample <- 0..959, channel <- 1..channels, into: <<>> do
          frequency = if channel == 1, do: 440, else: 660
          offset = packet_index * 960 + sample
          value = round(:math.sin(2 * :math.pi() * frequency * offset / 48_000) * 16_000)
          <<value::little-signed-16>>
        end

      assert {:ok, payload} = OpusEncoder.encode_packet(Map.fetch!(encoders, channels), pcm, 960)
      assert {:ok, ^channels} = Vxpipe.Gateway.WebRTC.OpusInput.packet_channels(payload)
      payload
    end)
  end
end
