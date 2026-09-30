defmodule Vxpipe.CallEngine.Integration.ElevenLabsTextToSpeechTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session, TTSUsage}
  alias Vxpipe.Providers.ElevenLabs.{TTS, TTSSession}
  alias Vxpipe.Providers.LiveModels

  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 60_000
  @phrase "Hello from Vxpipe."
  @sample_rate 16_000

  test "one short phrase streams credited raw PCM and measured generation usage" do
    assert {:ok, config} =
             TTS.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :tts),
               voice: LiveModels.speech("elevenlabs", :tts_voice),
               sample_rate: @sample_rate
             )

    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [
                 model: config.model,
                 voice: config.voice,
                 sample_rate: config.sample_rate
               ],
               private: [config: config],
               usage: true
             )

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :ready, readiness: :initialized} = ready},
                   5_000

    assert :ok = Session.ack(session, ready)
    assert {:ok, %{ref: request} = playback} = Session.speak(session, @phrase)
    deadline = System.monotonic_time(:millisecond) + 30_000
    {bytes, usage} = await_completion(session, request, deadline, 0)
    assert bytes > 0
    assert usage.input_characters == String.length(@phrase)
    assert usage.generated_bytes == bytes
    assert usage.generation == :completed
    assert usage.provenance == :locally_measured

    assert usage.usage_identity == %{
             provider: :elevenlabs,
             model: config.model,
             provenance: :locally_measured
           }

    # This consumer checks generation/credit, with no audible output device.
    assert :ok = Session.settle_output(session, playback, 0)
    assert :ok = Session.close(session)
  end

  defp await_completion(session, request, deadline, bytes) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "ElevenLabs synthesis exceeded its deadline"

    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request, payload: pcm} = audio} ->
        assert byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0

        assert bytes + byte_size(pcm) <= @sample_rate * 2 * 10,
               "short phrase exceeded ten seconds of PCM"

        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        await_completion(session, request, deadline, bytes + byte_size(pcm))

      {:vxpipe_speech,
       %Event{session: ^session, request_ref: ^request, kind: :input_submitted} = event} ->
        assert :ok = Session.ack(session, event)
        await_completion(session, request, deadline, bytes)

      {:vxpipe_speech,
       %Event{
         session: ^session,
         request_ref: ^request,
         kind: :completed,
         usage: %TTSUsage{} = usage
       } =
           event} ->
        assert :ok = Session.ack(session, event)
        {bytes, usage}

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("ElevenLabs session closed before synthesis completion")
    after
      remaining -> flunk("ElevenLabs synthesis did not complete")
    end
  end
end
