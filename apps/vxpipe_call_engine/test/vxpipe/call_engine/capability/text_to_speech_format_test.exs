defmodule Vxpipe.CallEngine.Capability.TextToSpeechFormatTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Capability.TextToSpeech.Tree
  alias Vxpipe.CallEngine.Speech.PrivateInit
  alias Vxpipe.CallEngine.{TestAudioOutputSink, TestTextToSpeechTransport, TextToSpeechRequest}
  alias Vxpipe.CallEngine.Usage.ProviderContext
  alias Vxpipe.Providers.ElevenLabs.{TTS, TTSSession}

  @voice "JBFqnCBsd6RMkjVDRZzb"

  for rate <- [8_000, 16_000, 24_000, 48_000] do
    @tag rate: rate
    test "normalizes #{rate} Hz ElevenLabs speech for playout without changing usage or credit",
         c do
      sink = start_supervised!({TestAudioOutputSink, observer: self(), block_output: true})
      {capability, wire} = start_capability(c.rate)
      request = request(sink)
      assert :ok = TextToSpeech.synthesize(capability, request)
      context = assert_open(wire)

      pcm = :binary.copy(<<100::little-signed-16>>, div(c.rate, 100))
      credit = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, pcm})
      assert_receive {:test_audio_output, ^sink, first}, 1_000
      assert_playout(first, 100, request)
      refute_receive {:test_tts_audio_result, ^credit, _result}
      assert :ok = GenServer.call(sink, {:complete_output, :ok})
      assert_receive {:test_tts_audio_result, ^credit, :ok}, 1_000

      pcm = :binary.copy(<<-200::little-signed-16>>, div(c.rate, 100))
      credit = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, pcm})
      assert_receive {:test_audio_output, ^sink, second}, 1_000
      assert_playout(second, -200, request)
      assert_receive {:test_tts_audio_result, ^credit, :ok}, 1_000

      TestTextToSpeechTransport.deliver_control(wire, {:final, context})
      assert_receive {:test_audio_output_finish, ^sink, "turn-format"}, 1_000
      refute_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      assert_receive {:vxpipe_tts_playback, ^capability, ^request, :completed}, 1_000
      assert_receive {:vxpipe_usage_observations, ^capability, observations}, 1_000

      assert Enum.any?(observations, fn observation ->
               observation.outcome == :succeeded and
                 observation.measurement.component == "generated_audio_duration" and
                 observation.measurement.quantity == 20
             end)
    end
  end

  defp assert_playout(frame, sample, request) do
    assert frame.sample_rate == 48_000
    assert frame.codec == :linear16
    assert frame.channels == 1
    assert frame.byte_order == :little
    assert frame.payload == :binary.copy(<<sample::little-signed-16>>, 480)
    assert frame.correlation_id == request.correlation_id
    assert frame.output_generation == request.output_generation
  end

  defp start_capability(rate) do
    {:ok, config} = TTS.new(api_key: "synthetic-elevenlabs", voice: @voice, sample_rate: rate)

    {:ok, private} =
      PrivateInit.open(
        [
          config: config,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: self()]
        ],
        5_000
      )

    {:ok, provider} =
      ProviderContext.new(name: "elevenlabs", integration_id: "format-test", model: config.model)

    tree =
      try do
        start_supervised!(
          {Tree,
           owner: self(),
           participant_id: "agent-format",
           provider: {TTSSession, [model: config.model, voice: @voice, sample_rate: rate]},
           provider_private: private,
           maximum_requests: 1,
           usage: [call_id: "call-format", activation_id: "activation-format", provider: provider]}
        )
      after
        PrivateInit.close(private)
      end

    capability = Tree.capability(tree)
    assert_receive {:test_tts_transport_started, wire, _connection}, 1_000
    assert_ready(capability)
    {capability, wire}
  end

  defp assert_ready(capability) do
    case TextToSpeech.readiness(capability) do
      {:ok, _resource, :preparing} ->
        _ = :sys.get_state(capability)
        assert_ready(capability)

      result ->
        assert {:ok, _resource, :ready} = result
    end
  end

  defp assert_open(wire) do
    assert_receive {:test_tts_control, ^wire, init}, 1_000
    assert %{"text" => " ", "context_id" => context} = JSON.decode!(init)

    for expected <- [
          %{"text" => "Hello", "context_id" => context},
          %{"context_id" => context, "flush" => true},
          %{"context_id" => context, "close_context" => true}
        ] do
      assert_receive {:test_tts_control, ^wire, payload}, 1_000
      assert JSON.decode!(payload) == expected
    end

    context
  end

  defp request(sink) do
    %TextToSpeechRequest{
      tenant_id: "tenant-format",
      room_id: "room-format",
      incarnation_id: "incarnation-format",
      participant_id: "agent-format",
      source_participant_id: "caller-format",
      connection_id: "connection-format",
      command_id: "command-format",
      correlation_id: "turn-format",
      output_id: "output-format",
      text: "Hello",
      output_generation: 3,
      output_sink: sink
    }
  end
end
