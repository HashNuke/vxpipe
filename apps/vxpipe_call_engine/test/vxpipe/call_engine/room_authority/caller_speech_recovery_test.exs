defmodule Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecoveryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{Handoff, Port, Recorder}
  alias Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecovery

  test "call details distinguish a failed cue from expiry during the same hearing phase" do
    identity = %{tenant_id: "tenant", call_id: "call", room_id: "room", incarnation_id: "rinc"}
    port = Port.new(Handoff.new(self(), 4), identity, %{"revision" => 0})
    token = "recovery-command"
    expiry = make_ref()

    episode = %{
      token: token,
      phase: :hearing,
      connection_id: "phone",
      room_turn_id: "turn",
      started_ms: 0,
      offset: 0,
      turn: make_ref(),
      session: %{generation: make_ref()},
      replacement: make_ref(),
      timer: {make_ref(), expiry}
    }

    connection = %{speech_recovery: episode, participant_id: "caller", pid: self()}

    state = %{
      held_participant_ids: MapSet.new(),
      connections: %{"phone" => connection},
      archive_recorder: %Recorder{port: port, participant_activations: %{}}
    }

    for {event, expected} <- [{:playout, "playout_failed"}, {:timeout, "deadline_expired"}] do
      case event do
        :playout -> CallerSpeechRecovery.playout(state, "phone", self(), token, :failed)
        :timeout -> CallerSpeechRecovery.expired(state, "phone", expiry)
      end

      assert_receive {:vxpipe_archive, :fact, _,
                      %{
                        payload: %{
                          "phase" => "carrier_exit",
                          "failed_phase" => "hearing",
                          "reason" => ^expected
                        }
                      }}
    end
  end
end
