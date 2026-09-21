defmodule Vxpipe.CallEngine.Integration.DeepgramFluxTextToSpeechTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech
  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech.Session, as: FluxSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}

  @moduletag :integration
  @moduletag timeout: 60_000

  test "native session streams nonempty 48 kHz linear16 audio and a terminal boundary" do
    config =
      FluxTextToSpeech.new!(
        api_key: System.fetch_env!("DEEPGRAM_API_KEY"),
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      )

    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: FluxSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [
                 config: config,
                 wire_options: [connect_timeout: 10_000, receive_timeout: 30_000]
               ],
               start_timeout: 15_000
             )

    assert %Event{kind: :ready, readiness: :provider_acknowledged} =
             ready = await_event(session, 15_000)

    assert :ok = Session.ack(session, ready)

    assert {:ok, %{ref: request}} =
             Session.speak(session, "Hello from the Vxpipe semantic speech test.")

    assert {audio_bytes, speech_id} = await_synthesis(session, request, 0, 20_000)
    assert audio_bytes > 0
    assert rem(audio_bytes, 2) == 0
    assert is_binary(speech_id)
    assert :ok = Session.close(session)
  end

  defp await_synthesis(session, request, audio_bytes, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_synthesis(session, request, audio_bytes, deadline)
  end

  defp do_await_synthesis(session, request, audio_bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request, payload: payload} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        do_await_synthesis(session, request, audio_bytes + byte_size(payload), deadline)

      {:vxpipe_speech,
       %Event{session: ^session, request_ref: ^request, kind: :input_submitted} = event} ->
        assert :ok = Session.ack(session, event)
        do_await_synthesis(session, request, audio_bytes, deadline)

      {:vxpipe_speech,
       %Event{
         session: ^session,
         request_ref: ^request,
         kind: :completed,
         provider_request_id: speech_id
       } = event} ->
        assert :ok = Session.ack(session, event)
        {audio_bytes, speech_id}

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request, kind: :failed} = event} ->
        flunk("Flux TTS failed: #{inspect(event.reason)}")

      {:vxpipe_speech_closed, ^session, reason} ->
        flunk("Flux TTS closed before completion: #{inspect(reason)}")
    after
      remaining -> flunk("timed out waiting for Flux TTS audio completion")
    end
  end

  defp await_event(session, timeout) do
    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} -> event
      {:vxpipe_speech_closed, ^session, reason} -> flunk("Flux TTS closed: #{inspect(reason)}")
    after
      timeout -> flunk("timed out waiting for Flux TTS readiness")
    end
  end
end
