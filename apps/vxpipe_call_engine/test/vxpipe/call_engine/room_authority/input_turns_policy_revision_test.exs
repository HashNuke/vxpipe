defmodule Vxpipe.CallEngine.RoomAuthority.InputTurnsPolicyRevisionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Event.ParticipantTurnStarted
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{InputTurns, State}

  @identity %{
    tenant_id: "tenant-input-turn",
    room_id: "room-input-turn",
    incarnation_id: "incarnation-input-turn",
    participant_id: "participant-input-turn",
    connection_id: "connection-input-turn"
  }

  test "a new provider policy session replaces an unfinished turn with the same provider index" do
    capability = self()
    state = state(capability)

    state = InputTurns.speech_to_text(capability, @identity, turn_started(0), state)

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: first_turn_id}}

    state = InputTurns.speech_to_text(capability, @identity, turn_started(1), state)

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: second_turn_id}}

    refute first_turn_id == second_turn_id

    turn = state.connections[@identity.connection_id].speech_to_text.turn
    assert turn.policy_revision == 1
  end

  defp state(capability) do
    recorder = %Recorder{port: nil, participant_activations: %{}}

    snapshot = %Snapshot{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      lifecycle: :open,
      created_by_actor_id: "actor-input-turn",
      created_by_command_id: "command-input-turn"
    }

    state = State.new(recorder, snapshot, %{})

    connection = %{
      actor_id: "actor-input-turn",
      participant_id: @identity.participant_id,
      pid: self(),
      output_sink: nil,
      role: :human,
      speech_to_text: %{capability: capability, turn: nil}
    }

    %{state | connections: %{@identity.connection_id => connection}}
  end

  defp turn_started(policy_revision) do
    %Signal{
      kind: :turn_started,
      provider_sequence: 1,
      policy_revision: policy_revision,
      provider_turn_index: 0,
      text: ""
    }
  end
end
