defmodule Vxpipe.Providers.MorseCodeApi.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Descriptor, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.MorseCodeApi.{Endpoint, STT, STTSession}

  test "readiness waits for provider acknowledgement and declares transcript onset and a Morse gap" do
    {session, wire} = start_session(false)
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.readiness == :provider_acknowledged
    assert descriptor.endpointing == :provider_gap
    assert descriptor.speech_start_evidence == :transcript
    assert descriptor.finite_input? == false
    assert descriptor.usage_identity.provider == :morse_code_api
    assert :ok = Descriptor.validate_conversational_stt(descriptor)
    refute_received {:vxpipe_speech, %Event{kind: :ready}}
    Wire.deliver(wire, {:ready, "morse-session"})
    assert event(session, :ready).readiness == :provider_acknowledged
  end

  test "only committed Morse silence ends a turn; revisions and keepalives do not" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:partial, "S"})
    started = event(session, :speech_started)
    assert event(session, :transcript).text == "S"
    Wire.deliver(wire, {:partial, "SOS TEST"})
    revised = event(session, :transcript)
    assert revised.turn_ref == started.turn_ref
    Wire.deliver(wire, {:partial, ""})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    Wire.deliver(wire, {:segment, "SOS TEST"})
    ended = event(session, :turn_ended)
    assert ended.turn_ref == started.turn_ref
    assert ended.text == "SOS TEST"
    assert ended.endpointing == :provider_gap
    assert ended.provider_request_id == "morse-session"
  end

  test "bounded input is forwarded once and identical committed replies retain separate turns" do
    {session, wire} = start_session()
    assert :ok = Session.push_audio(session, :binary.copy(<<0>>, 96_000))
    for _ <- 1..3, do: assert_receive({:scribe_audio, ^wire, pcm} when byte_size(pcm) == 32_000)

    refs =
      for _ <- 1..2 do
        Wire.deliver(wire, {:segment, "YES"})
        started = event(session, :speech_started)
        assert event(session, :transcript).text == "YES"
        assert event(session, :turn_ended).turn_ref == started.turn_ref
        started.turn_ref
      end

    assert length(Enum.uniq(refs)) == 2
    refute_received {:scribe_commit, _}
  end

  test "empty recognition does not invent turns and closing retires the owned wire" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:partial, " "})
    Wire.deliver(wire, {:segment, ""})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _}, 1_000
  end

  test "an unacknowledged connection fails within its startup deadline" do
    {session, wire} = start_session(false, setup_timeout_ms: 50)
    monitor = Process.monitor(wire)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :ready}}
  end

  test "a stalled partial fails without promoting it to a completed utterance" do
    {session, wire} = start_session(true, commit_timeout_ms: 100)
    Wire.deliver(wire, {:partial, "SOS"})
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "SOS"})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "losing the active socket retires recognition rather than claiming a transcript" do
    {session, wire} = start_session()
    GenServer.stop(wire, :normal)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  defp start_session(ready? \\ true, extra \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, endpoint} = Endpoint.new("http://localhost:8787", allow_http?: true)
    assert {:ok, config} = STT.new([api_key: "synthetic"], endpoint)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [],
               private:
                 extra ++ [config: config, wire_module: Wire, wire_options: [observer: self()]]
             )

    assert_receive {:scribe_started, wire}, 1_000

    if ready? do
      Wire.deliver(wire, {:ready, "morse-session"})
      _ = event(session, :ready)
    end

    {session, wire}
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
