defmodule Vxpipe.CallEngine.Integration.CartesiaTextToSpeechTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Cartesia.{TTS, TTSSession}
  alias Vxpipe.Providers.LiveModels

  @moduletag :live_providers
  @moduletag :live_cartesia
  @moduletag :capture_log
  @moduletag timeout: 60_000

  test "one short phrase completes with credited raw PCM and measured provider identity" do
    {:ok, config} =
      TTS.new(
        api_key: System.fetch_env!("CARTESIA_API_KEY"),
        model: LiveModels.speech("cartesia", :tts),
        voice: LiveModels.speech("cartesia", :tts_voice),
        sample_rate: 24_000
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
               private: [config: config]
             )

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :ready, readiness: :initialized} = ready},
                   5_000

    assert :ok = Session.ack(session, ready)

    assert {:ok, descriptor} = TTSSession.configure(model: config.model, voice: config.voice)

    assert descriptor.usage_identity == %{
             provider: :cartesia,
             model: config.model,
             provenance: :locally_measured
           }

    assert {:ok, %{ref: request} = playback} = Session.speak(session, "Hello from Vxpipe.")
    deadline = System.monotonic_time(:millisecond) + 30_000
    bytes = await_completion(session, request, deadline, 0)
    assert bytes > 0
    assert :ok = Session.settle_output(session, playback, div(bytes, 48))
    assert :ok = Session.close(session)
  end

  defp await_completion(session, request, deadline, bytes) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Cartesia synthesis exceeded its deadline"

    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request, payload: pcm} = audio} ->
        assert byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0

        assert bytes + byte_size(pcm) <= 24_000 * 2 * 10,
               "short phrase exceeded ten seconds of PCM"

        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        await_completion(session, request, deadline, bytes + byte_size(pcm))

      {:vxpipe_speech,
       %Event{session: ^session, request_ref: ^request, kind: :input_submitted} = event} ->
        assert :ok = Session.ack(session, event)
        await_completion(session, request, deadline, bytes)

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request, kind: :completed} = event} ->
        assert :ok = Session.ack(session, event)
        bytes

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("Cartesia session closed before synthesis completion")
    after
      remaining -> flunk("Cartesia synthesis did not complete")
    end
  end
end
