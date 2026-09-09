defmodule Vxpipe.CallEngine.Provider.MorseCode.LocalTransportTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.{SpeechToText, TextToSpeech}
  alias Vxpipe.CallEngine.Media.{AudioFrame, AudioOutputFrame}

  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Decoder, Encoder}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TextToSpeechRequest

  test "local STT decodes chunked PCM through the existing capability boundary" do
    assert {:ok, config} = MorseCodeSTT.new(unit_duration_ms: 20)
    identity = identity()

    capability =
      start_supervised!(
        {SpeechToText,
         identity ++
           [
             owner: self(),
             provider: {MorseCodeSTT, config},
             transport: {MorseCodeSTT.Transport, []}
           ]}
      )

    assert {:ok, pcm} = Encoder.encode(config, "SOS")

    pcm
    |> split_repeatedly([1, 637, 2_003, 17])
    |> Enum.with_index(1)
    |> Enum.each(fn {payload, sequence} ->
      assert :ok = SpeechToText.push_audio(capability, audio_frame(identity, sequence, payload))
    end)

    assert_receive {:vxpipe_stt_signal, ^capability, _, %Signal{kind: :connected}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{
                      kind: :turn_started,
                      provider_turn_index: 0,
                      text: ""
                    }}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, text: "S"}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, text: "SO"}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{kind: :transcript_updated, text: "SOS"}}

    assert_receive {:vxpipe_stt_signal, ^capability, _,
                    %Signal{
                      kind: :turn_ended,
                      provider_turn_index: 0,
                      text: "SOS",
                      trigger: "morse_end_gap"
                    }}
  end

  test "local TTS incrementally drains through the existing output sink" do
    assert {:ok, config} = MorseCodeTTS.new(unit_duration_ms: 20)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    participant_id = unique_id("agent")

    capability =
      start_supervised!(
        {TextToSpeech,
         owner: self(),
         participant_id: participant_id,
         provider: {MorseCodeTTS, config},
         transport: {
           MorseCodeTTS.Transport,
           [chunk_duration_ms: 20, emit_interval_ms: 0]
         },
         maximum_requests: 1,
         task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor}
      )

    request = request(participant_id, "turn-one", "ET", sink)
    assert :ok = TextToSpeech.synthesize(capability, request)

    frames = collect_output(sink, request.correlation_id, [])
    assert length(frames) > 10
    assert Enum.all?(frames, &(byte_size(&1.payload) <= 640))

    pcm = frames |> Enum.map(& &1.payload) |> IO.iodata_to_binary()
    assert {:ok, decoder} = Decoder.new(config)
    assert {:ok, decoder, events} = Decoder.push(decoder, pcm)
    assert {:ok, _decoder, []} = Decoder.flush(decoder)
    assert List.last(events) == {:final, "ET"}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}
  end

  test "local TTS interruption discards stale output and starts a replacement" do
    assert {:ok, config} = MorseCodeTTS.new(unit_duration_ms: 20)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    participant_id = unique_id("agent")

    capability =
      start_supervised!(
        {TextToSpeech,
         owner: self(),
         participant_id: participant_id,
         provider: {MorseCodeTTS, config},
         transport: {
           MorseCodeTTS.Transport,
           [chunk_duration_ms: 20, emit_interval_ms: 10]
         },
         maximum_requests: 1,
         task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor}
      )

    current = request(participant_id, "turn-old", "SOS SOS SOS", sink)
    replacement = request(participant_id, "turn-new", "E", sink)

    assert :ok = TextToSpeech.synthesize(capability, current)
    assert_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-old"}}
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert_receive {:vxpipe_tts_playback, ^capability, ^current, {:progress, 20, 100}}

    assert {:ok, [{^current, 20}]} = TextToSpeech.interrupt(capability)
    assert :ok = TextToSpeech.synthesize(capability, replacement)

    assert_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-new"}},
                   500

    refute_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-old"}},
                   100
  end

  defp collect_output(sink, correlation_id, frames) do
    receive do
      {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: ^correlation_id} = frame} ->
        collect_output(sink, correlation_id, [frame | frames])

      {:test_audio_output_finish, ^sink, ^correlation_id} ->
        Enum.reverse(frames)
    after
      2_000 -> flunk("timed out waiting for Morse audio output")
    end
  end

  defp identity do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))

    [
      tenant_id: "tenant-test",
      room_id: "room-#{suffix}",
      incarnation_id: "rinc-#{suffix}",
      participant_id: "human-#{suffix}",
      connection_id: "conn-#{suffix}"
    ]
  end

  defp audio_frame(identity, sequence, payload) do
    struct!(
      AudioFrame,
      identity ++
        [
          track_id: "track-morse",
          codec: :linear16,
          sample_rate: 16_000,
          channels: 1,
          sequence_number: sequence,
          timestamp: sequence * 320,
          payload: payload,
          received_at: System.monotonic_time(:millisecond)
        ]
    )
  end

  defp request(participant_id, correlation_id, text, sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "rinc-test",
      participant_id: participant_id,
      source_participant_id: "human-test",
      connection_id: "conn-test",
      command_id: unique_id("command"),
      correlation_id: correlation_id,
      text: text,
      output_sink: sink
    }
  end

  defp split_repeatedly(binary, sizes), do: split_repeatedly(binary, sizes, sizes, [])

  defp split_repeatedly(<<>>, _remaining_sizes, _all_sizes, chunks),
    do: Enum.reverse(chunks)

  defp split_repeatedly(binary, [], all_sizes, chunks),
    do: split_repeatedly(binary, all_sizes, all_sizes, chunks)

  defp split_repeatedly(binary, [size | sizes], all_sizes, chunks)
       when byte_size(binary) > size do
    <<chunk::binary-size(size), rest::binary>> = binary
    split_repeatedly(rest, sizes, all_sizes, [chunk | chunks])
  end

  defp split_repeatedly(binary, _sizes, _all_sizes, chunks),
    do: Enum.reverse([binary | chunks])

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
