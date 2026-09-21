defmodule Vxpipe.Providers.Google.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestGoogleSTTTransport
  alias Vxpipe.Providers.Google.{STT, STTSession}

  test "setup acknowledgement gates audio and correlated provider turns" do
    {session, wire} = start_session()
    assert_control(wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    refute_receive {:vxpipe_speech, %Event{kind: :ready}}, 20
    TestGoogleSTTTransport.deliver(wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready, readiness: :provider_acknowledged} = next_event(session)

    assert :ok = Session.push_audio(session, <<1, 0, 2, 0>>)
    assert_receive {:test_google_stt_audio, ^wire, <<1, 0, 2, 0>>}

    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_START"}}))
    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)

    TestGoogleSTTTransport.deliver(
      wire,
      ~s({"serverContent":{"interimInputTranscription":{"text":"hello"}}})
    )

    assert %Event{kind: :transcript, turn_ref: ^turn, text: "hello"} = next_event(session)
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_END"}}))
    refute_receive {:vxpipe_speech, %Event{kind: :turn_ended}}, 20

    TestGoogleSTTTransport.deliver(
      wire,
      ~s({"serverContent":{"inputTranscription":{"text":"hello there"}}})
    )

    assert %Event{
             kind: :turn_ended,
             turn_ref: ^turn,
             text: "hello there",
             endpointing: :provider_semantic
           } = next_event(session)
  end

  test "late final transcription stays with the previous ended turn" do
    {session, wire} = start_session()
    assert_control(wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready} = next_event(session)
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_START"}}))
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_END"}}))
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_START"}}))
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)

    TestGoogleSTTTransport.deliver(
      wire,
      ~s({"serverContent":{"inputTranscription":{"text":"first"}}})
    )

    assert %Event{kind: :turn_ended, turn_ref: ^first, text: "first"} = next_event(session)
    TestGoogleSTTTransport.deliver(wire, ~s({"voiceActivity":{"type":"ACTIVITY_END"}}))

    TestGoogleSTTTransport.deliver(
      wire,
      ~s({"serverContent":{"inputTranscription":{"text":"second"}}})
    )

    assert %Event{kind: :turn_ended, turn_ref: ^second, text: "second"} = next_event(session)
  end

  test "transport loss retires only the scoped allocation" do
    {session, wire} = start_session()
    assert_control(wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready} = next_event(session)
    TestGoogleSTTTransport.disconnect(wire)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
  end

  test "active socket crash retires its scoped allocation" do
    {session, wire} = start_session()
    assert_control(wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready} = next_event(session)
    GenServer.stop(wire, :simulated_connection_failure)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
  end

  test "renews on a prepared socket only after the current turn has finalized" do
    {session, first_wire} = start_session()
    assert_control(first_wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(first_wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready} = next_event(session)
    TestGoogleSTTTransport.deliver(first_wire, ~s({"voiceActivity":{"type":"ACTIVITY_START"}}))
    assert %Event{kind: :speech_started, turn_ref: first_turn} = next_event(session)

    send(Session.provider(session), :renew)
    assert_receive {:test_google_stt_started, second_wire, _connection}, 1_000
    refute second_wire == first_wire
    assert_control(second_wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(second_wire, ~s({"setupComplete":{}}))
    assert :ok = Session.push_audio(session, <<1, 0>>)
    assert_receive {:test_google_stt_audio, ^first_wire, <<1, 0>>}

    TestGoogleSTTTransport.deliver(first_wire, ~s({"voiceActivity":{"type":"ACTIVITY_END"}}))

    TestGoogleSTTTransport.deliver(
      first_wire,
      ~s({"serverContent":{"inputTranscription":{"text":"first"}}})
    )

    assert %Event{kind: :turn_ended, turn_ref: ^first_turn, text: "first"} = next_event(session)
    _ = :sys.get_state(Session.provider(session))

    assert :ok = Session.push_audio(session, <<2, 0>>)
    assert_receive {:test_google_stt_audio, ^second_wire, <<2, 0>>}
    refute_receive {:test_google_stt_audio, ^first_wire, <<2, 0>>}, 20
  end

  test "replacement socket failure leaves the active transcription socket usable" do
    {session, first_wire} = start_session()
    assert_control(first_wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    TestGoogleSTTTransport.deliver(first_wire, ~s({"setupComplete":{}}))
    assert %Event{kind: :ready} = next_event(session)

    send(Session.provider(session), :renew)
    assert_receive {:test_google_stt_started, pending_wire, _connection}, 1_000
    assert_control(pending_wire, %{"setup" => %{"model" => "models/gemini-3.5-transcribe-live"}})
    GenServer.stop(pending_wire, :simulated_connect_failure)

    assert :ok = Session.push_audio(session, <<1, 0>>)
    assert_receive {:test_google_stt_audio, ^first_wire, <<1, 0>>}
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = STT.new(api_key: "synthetic-key")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [
                 config: config,
                 wire_module: TestGoogleSTTTransport,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:test_google_stt_started, wire, _connection}, 1_000
    {session, wire}
  end

  defp assert_control(wire, %{"setup" => %{"model" => expected}}) do
    assert_receive {:test_google_stt_control, ^wire, payload}, 1_000
    assert %{"setup" => %{"model" => ^expected}} = JSON.decode!(payload)
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
