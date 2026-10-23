defmodule Vxpipe.Providers.Cartesia.TTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Providers.Cartesia.{TTS, TTSSession}

  @voice "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"

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
    assert_control(wire, %{"context_id" => context, "cancel" => true})

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

  test "direct close ends the transport without a provider goodbye message" do
    {session, wire} = start_session()
    provider = Session.provider(session)
    assert :ok = TTSSession.close(provider)
    assert_receive {:test_tts_transport_closed, ^wire}, 1_000
  end

  test "capability close tears down the owned transport" do
    {session, wire} = start_session()
    monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
  end

  test "audio and final between fencing and cancellation preserve the socket" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    context = assert_open(wire, "First")
    assert %Event{kind: :input_submitted} = next_event(session)
    assert {:ok, ticket} = Session.fence_output(session, request)
    reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, <<1, 0>>})
    assert_receive {:test_tts_audio_result, ^reference, :ok}
    TestTextToSpeechTransport.deliver_control(wire, {:final, context})
    _ = :sys.get_state(Session.provider(session))
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)
    assert {:ok, _next} = Session.speak(session, "Next")
    assert_open(wire, "Next")
  end

  test "cancellation uses a terminal already received while audio waits for credit" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    context = assert_open(wire, "First")
    assert %Event{kind: :input_submitted} = next_event(session)
    reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, <<1, 0>>})
    assert_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}
    TestTextToSpeechTransport.deliver_control(wire, {:final, context})
    _ = :sys.get_state(wire)
    _ = :sys.get_state(Session.provider(session))
    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    assert_receive {:test_tts_audio_result, ^reference, :ok}
    assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)
    assert {:ok, _next} = Session.speak(session, "Next")
    assert_open(wire, "Next")
  end

  test "a large final audio frame drains in credited chunks before completion" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    context = assert_open(wire, "First")
    assert %Event{kind: :input_submitted} = next_event(session)
    pcm = :binary.copy(<<1, 0>>, 80_000)
    reference = TestTextToSpeechTransport.deliver_audio_with_result(wire, {context, pcm})
    TestTextToSpeechTransport.deliver_control(wire, {:final, context})

    chunks =
      for _ <- 1..3 do
        assert_receive {:vxpipe_speech_audio,
                        %Audio{request_ref: ^request, payload: chunk} = audio},
                       1_000

        assert byte_size(chunk) <= 65_536
        refute_received {:test_tts_audio_result, ^reference, :ok}
        refute_received {:vxpipe_speech, %Event{kind: :completed}}
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        chunk
      end

    assert IO.iodata_to_binary(chunks) == pcm
    assert_receive {:test_tts_audio_result, ^reference, :ok}, 1_000
    assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
  end

  test "missing cancellation acknowledgement has a bounded failure deadline" do
    {session, wire} = start_session(cancel_timeout_ms: 100)
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    context = assert_open(wire, "First")
    assert %Event{kind: :input_submitted} = next_event(session)
    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    assert_control(wire, %{"context_id" => context, "cancel" => true})
    monitor = Process.monitor(wire)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{request_ref: ^request, kind: :cancelled}}
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

  defp start_session(overrides \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} = TTS.new(api_key: "synthetic-cartesia", voice: @voice)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [model: "sonic-3.6", voice: @voice, sample_rate: 24_000],
               private:
                 [
                   config: config,
                   wire_module: TestTextToSpeechTransport,
                   wire_options: [observer: self()]
                 ] ++ overrides
             )

    assert_receive {:test_tts_transport_started, wire, _connection}, 1_000
    assert %Event{kind: :ready, readiness: :initialized} = next_event(session)
    {session, wire}
  end

  defp assert_open(wire, text) do
    assert_receive {:test_tts_control, ^wire, payload}, 500

    assert %{
             "model_id" => "sonic-3.6",
             "transcript" => ^text,
             "voice" => %{"id" => @voice},
             "output_format" => %{
               "container" => "raw",
               "encoding" => "pcm_s16le",
               "sample_rate" => 24_000
             },
             "context_id" => context,
             "continue" => false
           } = JSON.decode!(payload)

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
