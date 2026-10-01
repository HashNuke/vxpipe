defmodule Vxpipe.CallEngine.Speech.RequestTTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestRequestTTS
  alias Vxpipe.Providers.Google.TTSSession, as: GoogleSession
  alias Vxpipe.Providers.Cartesia.TTSSession, as: CartesiaSession
  alias Vxpipe.Providers.ElevenLabs.TTSSession, as: ElevenLabsSession

  for provider <- [GoogleSession, CartesiaSession, ElevenLabsSession] do
    @tag request_provider: provider
    test "#{inspect(provider)} a streamed request releases each PCM chunk only after consumer credit",
         %{request_provider: provider} do
      session = start_session(provider)
      assert {:ok, %{ref: request} = handle} = Session.speak(session, "Hello")
      assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)
      assert_receive {:test_request_tts_started, worker, "Hello"}

      pcm = <<1, 0, 2, 0>>
      send(worker, {:audio, pcm})

      assert_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request, payload: ^pcm} = audio}
      refute_receive {:test_request_tts_audio_consumed, ^worker, :ok}, 20
      assert :ok = Session.validate_audio(session, audio)
      assert :ok = Session.ack_audio(session, audio)
      assert_receive {:test_request_tts_audio_consumed, ^worker, :ok}

      send(worker, :complete)
      assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
      assert :ok = Session.settle_output(session, handle, 1)
    end

    @tag request_provider: provider
    test "#{inspect(provider)} cancellation stops the request task before a replacement may publish",
         %{request_provider: provider} do
      session = start_session(provider)
      assert {:ok, %{ref: request}} = Session.speak(session, "First")
      assert %Event{kind: :input_submitted} = next_event(session)
      assert_receive {:test_request_tts_started, worker, "First"}
      monitor = Process.monitor(worker)

      assert {:ok, ticket} = Session.fence_output(session, request)
      assert {:ok, _playback} = Session.cancel(session, ticket, 0)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}
      assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)

      assert {:ok, %{ref: replacement}} = Session.speak(session, "Second")
      assert %Event{kind: :input_submitted, request_ref: ^replacement} = next_event(session)
      assert_receive {:test_request_tts_started, next_worker, "Second"}
      refute next_worker == worker
      send(worker, {:audio, <<1, 0>>})
      refute_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}, 20
      send(next_worker, :complete)
      assert %Event{kind: :completed, request_ref: ^replacement} = next_event(session)
    end

    @tag request_provider: provider
    test "#{inspect(provider)} a failed provider request closes the allocation without false completion",
         %{request_provider: provider} do
      session = start_session(provider)
      assert {:ok, %{ref: request}} = Session.speak(session, "Fail")
      assert %Event{kind: :input_submitted} = next_event(session)
      assert_receive {:test_request_tts_started, worker, "Fail"}
      send(worker, :fail)
      assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
      refute_receive {:vxpipe_speech, %Event{kind: :completed, request_ref: ^request}}, 20
    end
  end

  test "a killed provider cannot leave its request task running" do
    for provider <- [GoogleSession, CartesiaSession, ElevenLabsSession] do
      session = start_session(provider)
      assert {:ok, _request} = Session.speak(session, "Held")
      assert %Event{kind: :input_submitted} = next_event(session)
      assert_receive {:test_request_tts_started, worker, "Held"}, 1_000
      monitor = Process.monitor(worker)
      Process.exit(Session.provider(session), :kill)
      assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    end
  end

  defp start_session(provider) do
    tree =
      start_supervised!(
        Supervisor.child_spec({CapabilityTree, owner: self()}, id: {CapabilityTree, make_ref()})
      )

    {configuration, options} =
      case provider do
        GoogleSession ->
          {Vxpipe.Providers.Google.TTS, [voice: "Kore"]}

        CartesiaSession ->
          {Vxpipe.Providers.Cartesia.TTS, [voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"]}

        ElevenLabsSession ->
          {Vxpipe.Providers.ElevenLabs.TTS, [voice: "JBFqnCBsd6RMkjVDRZzb"]}
      end

    assert {:ok, config} = configuration.new(Keyword.put(options, :api_key, "synthetic-key"))
    config = %{config | endpoint: self()}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: provider,
               options: Keyword.put(options, :model, config.model),
               private: [config: config, request_module: TestRequestTTS]
             )

    assert %Event{kind: :ready, readiness: :initialized} = next_event(session)
    session
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
