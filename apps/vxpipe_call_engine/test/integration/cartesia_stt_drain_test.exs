defmodule Vxpipe.CallEngine.Integration.CartesiaSTTDrainTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  alias Vxpipe.CallEngine.TestSpeechUpgradeServer
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Cartesia.{STT, STTSession}

  test "coalesced final turn and normal peer close remain ordered through the real socket" do
    peer =
      start_supervised!(
        {TestSpeechUpgradeServer,
         owner: self(),
         frames: [text: JSON.encode!(%{type: "connected", request_id: "connection"})]}
      )

    assert_receive {:speech_upgrade_endpoint, endpoint}
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, config} = STT.new(api_key: "synthetic-key")
    config = %{config | endpoint: endpoint}

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [],
               private: [config: config]
             )

    assert %Event{kind: :ready} = next_event(session)
    assert :ok = STTSession.finish_input(Session.provider(session))

    :ok =
      GenServer.call(
        peer,
        {:send,
         [
           {:text, JSON.encode!(%{type: "turn.start", request_id: "connection"})},
           {:text,
            JSON.encode!(%{
              type: "turn.end",
              request_id: "connection",
              transcript: "Final words."
            })},
           {:close, 1_000, "synthetic-private-close-detail"}
         ]}
      )

    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^turn, text: "Final words."} = next_event(session)
    assert %Event{kind: :input_finished} = next_event(session)
    assert :ok = Session.close(session)
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
