defmodule Vxpipe.CallEngine.RoomAuthority.IdlePlayedTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Event.AgentTurnInterrupted
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{AgentOutput, State, TurnState}
  alias Vxpipe.CallEngine.TextToSpeechRequest

  test "queued zero-played phrases do not erase the interrupted current phrase's played time" do
    {:ok, old} =
      SendText.new(
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        actor_id: "actor",
        participant_id: "human",
        connection_id: "connection",
        correlation_id: "old",
        content: "old",
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    {:ok, origin} =
      SendText.new(
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        actor_id: "actor",
        participant_id: "human",
        connection_id: "connection",
        correlation_id: "idle",
        content: "idle",
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    current = %TextToSpeechRequest{
      tenant_id: old.tenant_id,
      room_id: old.room_id,
      incarnation_id: old.incarnation_id,
      participant_id: "agent",
      source_participant_id: old.participant_id,
      connection_id: old.connection_id,
      command_id: old.id,
      correlation_id: old.correlation_id,
      output_id: "current",
      text: "Current.",
      output_sink: self()
    }

    pending = %{current | output_id: "pending", text: "Pending."}

    capability =
      start_supervised!(
        {Vxpipe.CallEngine.TestScopedInterruptReply, [{current, 500}, {pending, 0}]}
      )

    state =
      State.new(
        %Recorder{port: nil, participant_activations: %{}},
        %Snapshot{
          tenant_id: "tenant",
          room_id: "room",
          incarnation_id: "incarnation",
          lifecycle: :open,
          created_by_actor_id: "actor",
          created_by_command_id: "command"
        },
        %{}
      )

    state = %{
      state
      | text_capability: %{module: :review_fixture, participant_id: "agent"},
        text_to_speech_capability: %{pid: capability},
        connections: %{"connection" => %{participant_id: "human", pid: self()}}
    }

    state =
      state
      |> TurnState.put(old)
      |> TurnState.admit_output(old)
      |> TurnState.begin_speech(current)
      |> TurnState.begin_speech(pending)

    state = TurnState.update(state, old, &%{&1 | generation_complete?: true})
    state = %{state | next_sequence: 2} |> TurnState.put(origin)
    assert {:ok, after_idle} = AgentOutput.interrupt_idle(origin, state)
    refute TurnState.active?(after_idle, old)
    assert TurnState.active?(after_idle, origin)

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{correlation_id: "old", played_ms: played}}

    assert played == 500
  end
end
