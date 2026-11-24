defmodule Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecoveryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{Handoff, Port, Recorder}
  alias Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecovery

  for scope <- [:held, :private_briefing] do
    test "a pending repeat timeout during #{scope} stops only the caller cue" do
      token = "pending-repeat"
      expiry = make_ref()
      owner = self()

      bystander =
        start_supervised!(
          {Task,
           fn ->
             receive do
               message -> send(owner, {:bystander_received, message})
             end
           end}
        )

      episode = %{token: token, timer: {make_ref(), expiry}, phase: :repeat}
      caller = %{participant_id: "caller", pid: owner, speech_recovery: episode}
      other = %{participant_id: "other", pid: bystander, speech_recovery: :eligible}

      state =
        struct(Vxpipe.CallEngine.RoomAuthority.State,
          connections: %{"phone" => caller, "second-phone" => other}
        )

      state =
        case unquote(scope) do
          :held -> %{state | held_participant_ids: MapSet.new(["caller"])}
          :private_briefing -> %{state | source_cutover: %{connection_id: "phone"}}
        end

      updated = CallerSpeechRecovery.expired(state, "phone", expiry)
      assert_receive {:stop_caller_recovery_cue, ^owner, ^token}
      assert updated.connections["phone"].speech_recovery == :eligible
      assert updated.connections["second-phone"] == other
      assert CallerSpeechRecovery.playout(updated, "phone", owner, token, :failed) == updated
      refute_received {:vxpipe_connection_unavailable, _}

      send(bystander, :barrier)
      assert_receive {:bystander_received, :barrier}
    end
  end

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
