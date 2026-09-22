defmodule Vxpipe.CallEngine.Speech.STSToolTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}

  test "explicit text can trigger a bounded tool call that accepts one result" do
    session = start_session()
    assert :ok = Session.push_text(session, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_submitted} = submitted}
    assert :ok = Session.ack(session, submitted)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :input_transcript} = transcript}

    assert :ok = Session.ack(session, transcript)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = call}
    assert :ok = Session.ack(session, call)
    assert call.tool_name == "echo"

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)

    provider = Session.provider(session)
    assert :ok = MorseSTS.send_tool_result(provider, call.call_ref, %{"ok" => true})

    assert :ok = Session.push_text(session, "STATUS")
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_submitted} = next}
    assert :ok = Session.ack(session, next)
  end

  test "unknown tool associations cannot accept results" do
    session = start_session()
    provider = Session.provider(session)
    assert {:error, :stale_request} = MorseSTS.send_tool_result(provider, make_ref(), %{})
  end

  test "interrupting with a pending tool call cancels it" do
    session = start_session()
    assert :ok = Session.push_text(session, "TOOL echo {\"text\":\"hi\"}")

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_submitted} = submitted}
    assert :ok = Session.ack(session, submitted)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :input_transcript} = transcript}

    assert :ok = Session.ack(session, transcript)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = call}
    assert :ok = Session.ack(session, call)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)

    provider = Session.provider(session)
    assert :ok = MorseSTS.interrupt(provider, call.turn_ref)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_cancelled} = cancelled}
    assert :ok = Session.ack(session, cancelled)
    assert cancelled.call_ref == call.call_ref
  end

  defp start_session do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope), provider: MorseSTS, owner: self())

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready}} = message, 5_000
    send(self(), message)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 5_000
    assert :ok = Session.ack(session, ready)
    session
  end
end
