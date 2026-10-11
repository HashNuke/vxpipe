defmodule Vxpipe.Providers.ElevenLabs.ContinuousSTTTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Descriptor, Event, Session}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

  test "VAD commit mode is continuous and does not prepare a local detector" do
    {session, wire} = start_session()
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.endpointing == :inferred_gap
    assert :ok = Descriptor.validate_conversational_stt(descriptor)
    assert :ok = Session.push_audio(session, :binary.copy(<<0>>, 64_000))

    for _ <- 1..2,
        do: assert_receive({:scribe_audio, ^wire, audio} when byte_size(audio) == 32_000)

    refute_received {:scribe_commit, _}
    refute_received {:scribe_started, _}
  end

  test "forced segments accumulate and continued partials cancel inferred endpoint" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:partial, "first"})
    start = event(session, :speech_started)
    assert event(session, :transcript).text == "first"
    Wire.deliver(wire, {:segment, "first final"})
    assert event(session, :transcript).text == "first final"
    Wire.deliver(wire, {:partial, "second"})
    transcript = event(session, :transcript)
    assert transcript.text == "first final second"
    assert transcript.turn_ref == start.turn_ref
    # An empty partial is a keepalive, never a turn end or lost retained text.
    Wire.deliver(wire, {:partial, ""})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    Wire.deliver(wire, {:segment, "second final"})
    assert event(session, :transcript).text == "first final second final"
    ended = event(session, :turn_ended)
    assert ended.text == "first final second final"
    assert ended.turn_ref == start.turn_ref
    assert ended.endpointing == :inferred_gap
    Wire.deliver(wire, {:partial, "third"})
    next = event(session, :speech_started)
    refute next.turn_ref == start.turn_ref
    assert event(session, :transcript).text == "third"
    refute_received {:scribe_started, _}
  end

  test "inferred gap waits for the retained draft to commit before settlement" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:segment, "first"})
    start = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "second"})
    assert event(session, :transcript).text == "first second"
    Wire.deliver(wire, {:partial, "second"})
    Wire.deliver(wire, {:segment, "second"})
    ended = event(session, :turn_ended)
    assert ended.turn_ref == start.turn_ref
    assert ended.text == "first second"
    assert ended.endpointing == :inferred_gap
  end

  test "an outstanding draft cannot settle and reopen a phantom turn through duplicate keepalives" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:segment, "first"})
    started = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "yes"})
    assert event(session, :transcript).text == "first yes"
    refute_receive {:vxpipe_speech, %Event{kind: :turn_ended}}, 200
    Wire.deliver(wire, {:partial, "yes"})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    Wire.deliver(wire, {:segment, "yes"})
    assert event(session, :turn_ended).turn_ref == started.turn_ref
  end

  test "blank segments do not create turns and late wire messages cannot reopen a closed allocation" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:partial, " "})
    Wire.deliver(wire, {:segment, ""})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _}
  end

  test "partial-only recognition fails within its commit deadline without inventing an endpoint" do
    {session, wire} = start_session(commit_timeout_ms: 100)
    Wire.deliver(wire, {:partial, "unfinished"})
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    monitor = Process.monitor(wire)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "registered provider close callback closes a continuous recognizer normally" do
    {session, wire} = start_session()
    monitor = Process.monitor(wire)
    assert :ok = STTSession.close(Session.provider(session))
    assert_receive {:DOWN, ^monitor, :process, ^wire, _}, 1_000
  end

  test "a draft after an earlier commit retains the bounded commit deadline" do
    {session, wire} = start_session(commit_timeout_ms: 100)
    Wire.deliver(wire, {:segment, "first"})
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "unfinished"})
    _ = event(session, :transcript)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "separately committed identical answers retain distinct turns" do
    {session, wire} = start_session()

    refs =
      for _ <- 1..2 do
        Wire.deliver(wire, {:segment, "yes"})
        started = event(session, :speech_started)
        assert event(session, :transcript).text == "yes"
        assert event(session, :turn_ended).turn_ref == started.turn_ref
        started.turn_ref
      end

    assert length(Enum.uniq(refs)) == 2
  end

  test "a stable post-commit draft requests one flush and awaits committed text" do
    {session, wire} = start_session()
    Wire.deliver(wire, {:segment, "first"})
    started = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "second"})
    assert event(session, :transcript).text == "first second"
    assert_receive {:scribe_commit, ^wire}, 1_000
    Wire.deliver(wire, {:partial, "second revised"})
    assert event(session, :transcript).text == "first second revised"
    refute_receive {:scribe_commit, ^wire}, 200
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    Wire.deliver(wire, {:segment, "second final"})
    assert event(session, :transcript).text == "first second final"
    ended = event(session, :turn_ended)
    assert ended.turn_ref == started.turn_ref
    assert ended.text == "first second final"
    assert ended.endpointing == :inferred_gap
  end

  test "an unacknowledged draft flush fails within its own deadline" do
    {session, wire} = start_session(flush_timeout_ms: 100)
    Wire.deliver(wire, {:segment, "first"})
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "draft"})
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "a blank flush response cannot promote an uncommitted draft or clear its deadline" do
    {session, wire} = start_session(flush_timeout_ms: 200)
    Wire.deliver(wire, {:segment, "first"})
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    Wire.deliver(wire, {:partial, "draft not committed"})
    _ = event(session, :transcript)
    assert_receive {:scribe_commit, ^wire}, 1_000
    Wire.deliver(wire, {:segment, " "})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  defp start_session(extra_private \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [commit_strategy: :vad],
               private:
                 extra_private ++
                   [
                     config: config,
                     wire_module: Wire,
                     wire_options: [observer: self()],
                     inferred_gap_ms: 100,
                     activity_options: [load: fn -> flunk("loaded Silero") end]
                   ]
             )

    assert_receive {:scribe_started, wire}, 1_000
    Wire.deliver(wire, {:ready, "synthetic"})
    _ = event(session, :ready)
    {session, wire}
  end

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
