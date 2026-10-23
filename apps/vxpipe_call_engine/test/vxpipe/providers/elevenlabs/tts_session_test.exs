defmodule Vxpipe.Providers.ElevenLabs.TTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Providers.ElevenLabs.{TTS, TTSSession}

  @voice "JBFqnCBsd6RMkjVDRZzb"

  test "reuses one transport across two utterances with per-utterance completion" do
    {session, wire} = start_session()
    assert {:ok, %{ref: first} = handle} = Session.speak(session, "Hello")
    first_context = assert_open(wire, "Hello")
    assert %Event{kind: :input_submitted, request_ref: ^first} = next_event(session)

    complete_utterance(session, wire, first, first_context, <<1, 0, 2, 0>>)
    assert :ok = Session.settle_output(session, handle, 1)

    assert {:ok, %{ref: second} = _handle} = Session.speak(session, "Again")
    second_context = assert_open(wire, "Again")
    refute second_context == first_context
    assert %Event{kind: :input_submitted, request_ref: ^second} = next_event(session)

    complete_utterance(session, wire, second, second_context, <<3, 0>>)

    refute_receive {:test_tts_transport_started, _, _}, 20
  end

  test "cancellation ends the utterance without ending the transport" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    context = assert_open(wire, "First")
    assert %Event{kind: :input_submitted} = next_event(session)

    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)

    wire_ref = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, <<1, 0>>})
    assert_receive {:test_tts_audio_result, ^wire_ref, :ok}
    refute_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}, 20

    TestTextToSpeechTransport.deliver_control(wire, {:final, context})
    assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)

    assert {:ok, %{ref: _replacement} = _handle} = Session.speak(session, "Second")
    replacement_context = assert_open(wire, "Second")
    refute replacement_context == context
  end

  test "stale frames from a finished context cannot leak into the next utterance" do
    {session, wire} = start_session()
    assert {:ok, %{ref: first} = handle} = Session.speak(session, "Hello")
    first_context = assert_open(wire, "Hello")
    assert %Event{kind: :input_submitted, request_ref: ^first} = next_event(session)
    complete_utterance(session, wire, first, first_context, <<1, 0>>)
    assert :ok = Session.settle_output(session, handle, 1)

    assert {:ok, %{ref: second} = _handle} = Session.speak(session, "Again")
    second_context = assert_open(wire, "Again")
    assert %Event{kind: :input_submitted, request_ref: ^second} = next_event(session)

    stale_ref =
      TestTextToSpeechTransport.deliver_audio_with_result(wire, {first_context, <<9, 0>>})

    assert_receive {:test_tts_audio_result, ^stale_ref, :ok}
    refute_receive {:vxpipe_speech_audio, %Audio{payload: <<9, 0>>}}, 20

    TestTextToSpeechTransport.deliver_control(wire, {:final, first_context})
    refute_receive {:vxpipe_speech, %Event{kind: :completed}}, 20
    refute_receive {:vxpipe_speech, %Event{kind: :cancelled}}, 20

    complete_utterance(session, wire, second, second_context, <<3, 0>>)
  end

  test "connection loss fails the session closed without replay" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "Hello")
    assert_open(wire, "Hello")
    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)

    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    TestTextToSpeechTransport.disconnect(wire, :connection_lost)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_receive {:vxpipe_speech, %Event{kind: :completed, request_ref: ^request}}, 20
  end

  test "a synthesis deadline retires a stalled allocation without a false completion" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "Stalled")
    assert_open(wire, "Stalled")
    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    send(provider, {:request_timeout, request})
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_receive {:vxpipe_speech, %Event{kind: :completed, request_ref: ^request}}, 20
  end

  test "direct close finishes the socket without dropping the goodbye" do
    {session, wire} = start_session()
    provider = Session.provider(session)
    assert :ok = TTSSession.close(provider)
    assert_control(wire, %{"close_socket" => true})
    assert_receive {:test_tts_transport_closed, ^wire}, 1_000
  end

  test "capability close tears down the owned transport" do
    {session, wire} = start_session()
    monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
  end

  defp complete_utterance(session, wire, request, context, pcm) do
    wire_ref = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, pcm})

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request, payload: ^pcm} = audio}

    assert :ok = Session.validate_audio(session, audio)
    TestTextToSpeechTransport.deliver_control(wire, {:final, context})
    refute_receive {:vxpipe_speech, %Event{kind: :completed}}, 20
    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_tts_audio_result, ^wire_ref, :ok}
    assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} = TTS.new(api_key: "synthetic-elevenlabs", voice: @voice)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [model: "eleven_flash_v2_5", voice: @voice, sample_rate: 16_000],
               private: [
                 config: config,
                 wire_module: TestTextToSpeechTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:test_tts_transport_started, wire, _connection}, 1_000
    assert %Event{kind: :ready, readiness: :initialized} = next_event(session)
    {session, wire}
  end

  defp assert_open(wire, text) do
    assert_receive {:test_tts_control, ^wire, init}, 500
    assert %{"text" => " ", "context_id" => context} = JSON.decode!(init)
    assert_receive {:test_tts_control, ^wire, body}, 500
    assert %{"text" => ^text, "context_id" => ^context} = JSON.decode!(body)
    assert_control(wire, %{"context_id" => context, "flush" => true})
    assert_control(wire, %{"context_id" => context, "close_context" => true})
    context
  end

  defp assert_control(wire, expected) do
    assert_receive {:test_tts_control, ^wire, payload}, 500
    assert JSON.decode!(payload) == expected
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
