defmodule Vxpipe.CallEngine.Provider.MorseCode.LocalTransportTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Media.AudioOutputFrame

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS
  alias Vxpipe.CallEngine.Provider.MorseCode.Decoder
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TextToSpeechRequest

  test "local TTS drains a long request completely through bounded output frames" do
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

    assert {:ok, readiness, :ready} = TextToSpeech.readiness(capability)
    assert readiness.scope == {:participant, participant_id}

    text = "PACK MY BOX WITH FIVE DOZEN JUGS"
    request = request(participant_id, "turn-one", text, sink)
    assert :ok = TextToSpeech.synthesize(capability, request)

    frames = collect_output(sink, request.correlation_id, [])
    assert length(frames) > 100
    assert Enum.all?(frames, &(byte_size(&1.payload) <= 640))

    pcm = frames |> Enum.map(& &1.payload) |> IO.iodata_to_binary()
    assert {:ok, decoder} = Decoder.new(config)
    assert {:ok, decoder, events} = Decoder.push(decoder, pcm)
    assert {:ok, _decoder, []} = Decoder.flush(decoder)
    assert List.last(events) == {:final, text}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}
  end

  test "local TTS holds at most one unacknowledged output frame" do
    assert {:ok, config} = MorseCodeTTS.new(unit_duration_ms: 20)
    sink = start_supervised!({TestAudioOutputSink, observer: self(), block_output: true})
    participant_id = unique_id("agent")

    capability =
      start_supervised!(
        {TextToSpeech,
         owner: self(),
         participant_id: participant_id,
         provider: {MorseCodeTTS, config},
         transport: {MorseCodeTTS.Transport, [emit_interval_ms: 0]},
         maximum_requests: 1,
         task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor}
      )

    request = request(participant_id, "turn-blocked", "ET", sink)
    assert :ok = TextToSpeech.synthesize(capability, request)
    assert_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-blocked"}}

    refute_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-blocked"}},
                   100
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

    assert_receive {:test_audio_output, ^sink,
                    %AudioOutputFrame{correlation_id: "turn-new"} = first_replacement},
                   500

    refute_receive {:test_audio_output, ^sink, %AudioOutputFrame{correlation_id: "turn-old"}},
                   100

    replacement_frames = [first_replacement | collect_output(sink, "turn-new", [])]
    replacement_pcm = replacement_frames |> Enum.map(& &1.payload) |> IO.iodata_to_binary()
    assert {:ok, decoder} = Decoder.new(config)
    assert {:ok, decoder, replacement_events} = Decoder.push(decoder, replacement_pcm)
    assert {:ok, _decoder, []} = Decoder.flush(decoder)
    assert List.last(replacement_events) == {:final, "E"}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_tts_playback, ^capability, ^replacement, :completed}
  end

  test "local TTS reports unsupported text instead of truncating or inventing audio" do
    assert {:ok, config} = MorseCodeTTS.new(unit_duration_ms: 20)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    participant_id = unique_id("agent")

    capability =
      start_supervised!(
        {TextToSpeech,
         owner: self(),
         participant_id: participant_id,
         provider: {MorseCodeTTS, config},
         transport: {MorseCodeTTS.Transport, [emit_interval_ms: 0]},
         maximum_requests: 1,
         task_supervisor: Vxpipe.CallEngine.AudioOutputTaskSupervisor}
      )

    monitor = Process.monitor(capability)
    invalid = request(participant_id, "turn-invalid", "NOT SUPPORTED %", sink)
    assert :ok = TextToSpeech.synthesize(capability, invalid)
    assert_receive {:vxpipe_tts_unavailable, ^capability, :provider_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^capability, :provider_failed}, 1_000
    refute_receive {:test_audio_output, ^sink, %AudioOutputFrame{}}
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
      output_id: unique_id("output"),
      text: text,
      output_sink: sink
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
