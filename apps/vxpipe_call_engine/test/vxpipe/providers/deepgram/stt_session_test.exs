defmodule Vxpipe.Providers.Deepgram.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestSpeechToTextTransport, as: Wire
  alias Vxpipe.Providers.Deepgram.{Flux, STTSession}

  test "a finalize request during a turn asks Flux to force its end of turn" do
    {session, wire} = start_session()
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.turn_finalize?

    Wire.deliver(wire, turn_info("StartOfTurn", 1, "hello"))
    started = event(session, :speech_started)
    _ = event(session, :transcript)

    assert :ok = Session.input_activity(session, :ended)
    assert_receive {:test_stt_control, ^wire, control}
    assert JSON.decode!(control) == %{"type" => "ForceEndTurn"}

    Wire.deliver(wire, turn_info("EndOfTurn", 2, "hello there", "manual"))
    ended = event(session, :turn_ended)
    assert ended.turn_ref == started.turn_ref
    assert ended.text == "hello there"
  end

  test "a forced end racing Flux's own end of turn is a harmless warning" do
    {session, wire} = start_session()
    Wire.deliver(wire, turn_info("StartOfTurn", 1, "yes"))
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert :ok = Session.input_activity(session, :ended)
    assert_receive {:test_stt_control, ^wire, _control}
    Wire.deliver(wire, turn_info("EndOfTurn", 2, "yes", "model"))
    _ = event(session, :turn_ended)

    Wire.deliver(
      wire,
      JSON.encode!(%{
        "type" => "Warning",
        "code" => "FORCE_END_TURN_NO_ACTIVE_TURN",
        "description" => "no active turn"
      })
    )

    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech_closed, ^session, _reason}
  end

  test "a finalize request without an open Flux turn sends nothing" do
    {session, wire} = start_session()
    assert :ok = Session.input_activity(session, :ended)
    refute_receive {:test_stt_control, ^wire, _control}, 100
  end

  defp start_session do
    tree = start_supervised!({CapabilityTree, owner: self()})
    options = [model: "flux-general-en", encoding: :linear16, sample_rate: 16_000]
    assert {:ok, config} = Flux.new([api_key: "synthetic-key"] ++ options)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: options,
               private: [
                 config: config,
                 wire_module: Wire,
                 wire_options: [observer: self(), ready_on_start: true]
               ]
             )

    assert_receive {:test_stt_transport_started, wire, _connection}
    _ = event(session, :ready)
    {session, wire}
  end

  defp turn_info(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    JSON.encode!(if trigger, do: Map.put(message, "trigger", trigger), else: message)
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
