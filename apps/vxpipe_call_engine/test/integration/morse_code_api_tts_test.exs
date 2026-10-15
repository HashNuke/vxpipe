defmodule Vxpipe.CallEngine.Integration.MorseCodeApiTTSTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_morse_code_api
  @moduletag :capture_log
  @moduletag timeout: 90_000

  alias Vxpipe.CallEngine.{LiveContextTTSSocket, LiveTTSCancellation}
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.MorseCodeApi.{CredentialValidation, TTS, TTSSession}

  test "persistent API sessions produce independently decoded PCM across utterances" do
    key = "vxpipe compatibility smoke key"
    assert {:ok, request} = CredentialValidation.request("api_key", %{"api_key" => key})

    assert {:ok, %{status: 200, body: models}} =
             Req.get(
               Keyword.merge(request, redirect: false, retry: false, receive_timeout: 10_000)
             )

    assert Enum.any?(models, &(&1["model_id"] == "morse_v1"))

    for rate <- [8_000, 16_000, 24_000, 48_000] do
      tree = start_supervised!({CapabilityTree, owner: self()}, id: {CapabilityTree, rate})
      assert {:ok, config} = TTS.new(api_key: key, sample_rate: rate)
      assert {:ok, local} = Config.new(sample_rate: rate)

      assert {:ok, session, :starting} =
               Session.start(CapabilityTree.scope(tree),
                 provider: TTSSession,
                 options: [model: config.model, voice: config.voice, sample_rate: rate],
                 private: [
                   config: config,
                   wire_module: LiveContextTTSSocket,
                   wire_options: [observer: self()]
                 ]
               )

      assert_receive {:live_tts_socket, wire}, 5_000
      monitor = Process.monitor(wire)
      assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 5_000
      assert :ok = Session.ack(session, ready)
      if rate == 16_000, do: LiveTTSCancellation.check(session)

      for {phrase, units} <- [{"SOS TEST", 69}, {"TEST", 35}] do
        assert {:ok, decoder} = Decoder.new(local)
        assert {:ok, %{ref: request} = playback} = Session.speak(session, phrase)
        deadline = System.monotonic_time(:millisecond) + 15_000
        {decoder, events, bytes} = collect(session, request, decoder, [], 0, deadline)
        assert {:ok, _, final} = Decoder.flush(decoder)
        assert for({:final, text} <- events ++ final, do: text) == [phrase]
        assert bytes == div(rate * units * 60 * 2, 1_000)
        assert :ok = Session.settle_output(session, playback, 0)
      end

      refute_received {:live_tts_socket, _replacement}
      refute_received {:DOWN, ^monitor, :process, ^wire, _reason}
      assert :ok = Session.close(session)
      assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 5_000
    end
  end

  defp collect(session, request, decoder, events, bytes, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Morse TTS exceeded its completion deadline"

    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request, payload: pcm} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert {:ok, decoder, next} = Decoder.push(decoder, pcm)
        assert :ok = Session.ack_audio(session, audio)
        collect(session, request, decoder, events ++ next, bytes + byte_size(pcm), deadline)

      {:vxpipe_speech,
       %Event{session: ^session, request_ref: ^request, kind: :input_submitted} = event} ->
        assert :ok = Session.ack(session, event)
        collect(session, request, decoder, events, bytes, deadline)

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request, kind: :completed} = event} ->
        assert :ok = Session.ack(session, event)
        {decoder, events, bytes}

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("Morse TTS closed before completing its utterance")
    after
      remaining -> flunk("Morse TTS did not complete its utterance")
    end
  end
end
