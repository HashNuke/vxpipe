defmodule Vxpipe.Providers.Cartesia.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Descriptor, Event, Session}
  alias Vxpipe.CallEngine.TestCartesiaSTTTransport, as: Wire
  alias Vxpipe.Providers.Cartesia.{STT, STTSession}

  test "configuration declares only provider-evidenced turn and finite-input behavior" do
    assert {:ok, descriptor} = STTSession.configure([])
    assert :ok = Descriptor.validate_conversational_stt(descriptor)
    assert descriptor.eager_end? and descriptor.resume? and descriptor.finite_input?

    assert descriptor.usage_identity == %{
             provider: :cartesia,
             model: "ink-2",
             provenance: :locally_measured
           }

    assert {:error, :invalid_configuration} = STTSession.configure(api_key: "secret")
  end

  test "provider acknowledgement gates cumulative updates, eager resume and distinct turns" do
    {session, wire} = start_session()
    refute_receive {:vxpipe_speech, %Event{kind: :ready}}, 20
    ready(session, wire)
    assert :ok = Session.push_audio(session, <<1, 0>>)
    assert_receive {:cartesia_stt_audio, ^wire, <<1, 0>>}
    deliver(wire, "turn.start")
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    deliver(wire, "turn.update", "Hello")
    assert %Event{kind: :transcript, turn_ref: ^first, text: "Hello"} = next_event(session)
    deliver(wire, "turn.update", "Hello there")
    assert %Event{kind: :transcript, turn_ref: ^first, text: "Hello there"} = next_event(session)
    deliver(wire, "turn.eager_end", "Hello there")

    assert %Event{kind: :eager_turn_ended, turn_ref: ^first, endpointing: :provider_semantic} =
             next_event(session)

    deliver(wire, "turn.resume")
    assert %Event{kind: :turn_resumed, turn_ref: ^first} = next_event(session)
    deliver(wire, "turn.end", "Hello there again.")

    assert %Event{kind: :turn_ended, turn_ref: ^first, text: "Hello there again."} =
             next_event(session)

    deliver(wire, "turn.start")
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)
    refute second == first
    deliver(wire, "turn.end", "Second.")
    assert %Event{kind: :turn_ended, turn_ref: ^second, text: "Second."} = next_event(session)
  end

  test "finite input drains final recognition before terminal evidence and is idempotent" do
    {session, wire} = start_session()
    ready(session, wire)
    deliver(wire, "turn.start")
    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert :ok = STTSession.finish_input(Session.provider(session))
    assert_receive {:cartesia_stt_finish_input, ^wire}
    assert :ok = STTSession.finish_input(Session.provider(session))
    refute_received {:cartesia_stt_finish_input, ^wire}
    refute_received {:vxpipe_speech, %Event{kind: :input_finished}}
    deliver(wire, "turn.end", "Final buffered words.")
    :ok = Wire.peer_close(wire, :normal_or_no_status)

    assert %Event{kind: :turn_ended, turn_ref: ^turn, text: "Final buffered words."} =
             next_event(session)

    assert %Event{kind: :input_finished} = next_event(session)
    assert :ok = STTSession.finish_input(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :input_finished}}
  end

  for failure <- [
        :unexpected_close,
        :incomplete_turn,
        :abnormal_close,
        :disconnect,
        :drain_timeout
      ] do
    test "#{failure} cannot fabricate finite completion" do
      {session, wire} = start_session()
      ready(session, wire)

      if unquote(failure) == :incomplete_turn do
        deliver(wire, "turn.start")
        assert %Event{kind: :speech_started} = next_event(session)
      end

      unless unquote(failure) == :unexpected_close do
        assert :ok = STTSession.finish_input(Session.provider(session))
        assert_receive {:cartesia_stt_finish_input, ^wire}
      end

      case unquote(failure) do
        :drain_timeout -> send(Session.provider(session), :drain_timeout)
        :disconnect -> Wire.disconnect(wire)
        :abnormal_close -> Wire.peer_close(wire, 1_008)
        _normal_close -> Wire.peer_close(wire, :normal_or_no_status)
      end

      assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
      refute_received {:vxpipe_speech, %Event{kind: :input_finished}}
    end
  end

  test "startup timeout and provider failure retire owned transport without secret output" do
    {session, wire} = start_session()
    monitor = Process.monitor(wire)
    send(Session.provider(session), :setup_timeout)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
  end

  test "hard provider death retires its sibling socket through allocation ownership" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)
    Process.exit(Session.provider(session), :kill)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
  end

  test "local close aborts socket without claiming drained input" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :input_finished}}
  end

  test "invalid connection identity and raw errors fail closed with redacted status" do
    {session, wire} = start_session()
    ready(session, wire)

    refute inspect(:sys.get_status(Session.provider(session)), limit: :infinity) =~
             "synthetic-key"

    Wire.deliver(wire, %{type: "turn.start", request_id: "wrong-connection"})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = STT.new(api_key: "synthetic-key")

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [],
               private: [config: config, wire_module: Wire, wire_options: [observer: self()]]
             )

    assert_receive {:cartesia_stt_started, wire, _connection}, 1_000
    {session, wire}
  end

  defp ready(session, wire) do
    deliver(wire, "connected")

    assert %Event{
             kind: :ready,
             readiness: :provider_acknowledged,
             provider_request_id: "connection"
           } = next_event(session)
  end

  defp deliver(wire, type, text \\ nil) do
    event = %{type: type, request_id: "connection"}
    event = if text, do: Map.put(event, :transcript, text), else: event
    :ok = Wire.deliver(wire, event)
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
