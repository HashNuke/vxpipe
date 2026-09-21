defmodule Vxpipe.Providers.Rime.TTSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Providers.Rime.{TTS, TTSSession}

  test "serialized synthesis completes only after credited audio and done" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request} = handle} = Session.speak(session, "Hello")
    assert_control(wire, %{"text" => "Hello"})
    assert_control(wire, %{"operation" => "flush"})
    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)

    pcm = <<1, 0, 2, 0>>
    wire_ref = TestTextToSpeechTransport.deliver_audio_with_result(wire, pcm)

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request, payload: ^pcm} = audio}

    assert :ok = Session.validate_audio(session, audio)
    TestTextToSpeechTransport.deliver_control(wire, ~s({"type":"done"}))
    refute_receive {:vxpipe_speech, %Event{kind: :completed}}, 20

    assert :ok = Session.ack_audio(session, audio)
    assert_receive {:test_tts_audio_result, ^wire_ref, :ok}
    assert %Event{kind: :completed, request_ref: ^request} = next_event(session)
    assert :ok = Session.settle_output(session, handle, 1)
    assert {:ok, %{ref: second}} = Session.speak(session, "Again")
    refute second == request
    assert_control(wire, %{"text" => "Again"})
    assert_control(wire, %{"operation" => "flush"})
  end

  test "cancellation drops late audio until the provider batch ends" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "First")
    assert_control(wire, %{"text" => "First"})
    assert_control(wire, %{"operation" => "flush"})
    assert %Event{kind: :input_submitted} = next_event(session)

    assert {:ok, ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, ticket, 0)
    wire_ref = TestTextToSpeechTransport.deliver_audio_with_result(wire, <<1, 0>>)
    assert_receive {:test_tts_audio_result, ^wire_ref, :ok}
    refute_receive {:vxpipe_speech_audio, %Audio{request_ref: ^request}}, 20
    TestTextToSpeechTransport.deliver_control(wire, ~s({"type":"done"}))
    assert %Event{kind: :cancelled, request_ref: ^request} = next_event(session)

    assert {:ok, %{ref: replacement}} = Session.speak(session, "Second")
    refute replacement == request
  end

  test "a synthesis deadline retires a stalled allocation without a false completion" do
    {session, wire} = start_session()
    assert {:ok, %{ref: request}} = Session.speak(session, "Stalled")
    assert_control(wire, %{"text" => "Stalled"})
    assert_control(wire, %{"operation" => "flush"})
    assert %Event{kind: :input_submitted} = next_event(session)
    provider = Session.provider(session)
    monitor = Process.monitor(provider)
    send(provider, {:request_timeout, request})
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_receive {:vxpipe_speech, %Event{kind: :completed, request_ref: ^request}}, 20
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             TTS.new(api_key: "synthetic-rime-key", model: "coda", speaker: "astra")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: TTSSession,
               options: [model: "coda", speaker: "astra", sample_rate: 24_000],
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
