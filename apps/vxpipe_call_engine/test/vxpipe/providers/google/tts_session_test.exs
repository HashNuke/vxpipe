defmodule Vxpipe.Providers.Google.TTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestGoogleTTSRequest
  alias Vxpipe.Providers.Google.{TTS, TTSSession}

  test "a streamed request releases each PCM chunk only after consumer credit" do
    session = start_session()
    assert {:ok, %{ref: request} = handle} = Session.speak(session, "Hello")
    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)
    assert_receive {:test_google_tts_started, worker, "Hello"}

    pcm = <<1, 0, 2, 0>>
    send(worker, {:audio, pcm})

    assert_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request, payload: ^pcm} = audio}
    refute_receive {:test_google_tts_audio_consumed, ^worker, :ok}, 20
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_google_tts_audio_consumed, ^worker, :ok}

    send(worker, :complete)
    assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
    assert :ok = Session.settle_output(session, handle, 1)
  end

  test "cancellation stops the request task before a replacement may publish" do
    session = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    assert %Event{kind: :input_submitted} = next_event(session)
    assert_receive {:test_google_tts_started, worker, "First"}
    monitor = Process.monitor(worker)

    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}
    assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)

    assert {:ok, %{ref: replacement}} = Session.speak(session, "Second")
    assert %Event{kind: :input_submitted, request_ref: ^replacement} = next_event(session)
    assert_receive {:test_google_tts_started, next_worker, "Second"}
    refute next_worker == worker
    send(worker, {:audio, <<1, 0>>})
    refute_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}, 20
    send(next_worker, :complete)
    assert %Event{kind: :completed, request_ref: ^replacement} = next_event(session)
  end

  test "a failed provider request closes the allocation without false completion" do
    session = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "Fail")
    assert %Event{kind: :input_submitted} = next_event(session)
    assert_receive {:test_google_tts_started, worker, "Fail"}
    send(worker, :fail)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_receive {:vxpipe_speech, %Event{kind: :completed, request_ref: ^request}}, 20
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = TTS.new(api_key: "synthetic-key", voice: "Kore")
    config = %{config | endpoint: self()}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [model: config.model, voice: config.voice],
               private: [config: config, request_module: TestGoogleTTSRequest]
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
