defmodule Vxpipe.CallEngine.RoomAuthority.AgentOutputTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff, Port, Recorder}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Event.AgentTurnInterrupted
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{AgentOutput, State, TurnState}
  alias Vxpipe.CallEngine.{TestCollectingArchiveWriter, TurnInterrupter}

  test "publishes an interrupted turn to both the client and private archive" do
    handoff = open_archive()

    recorder = %Recorder{
      port:
        Port.new(
          handoff,
          %{
            tenant_id: "tenant-test",
            call_id: "call-test",
            room_id: "room-test",
            incarnation_id: "incarnation-test"
          },
          %{"revision" => 0}
        ),
      participant_activations: %{"agent-test" => "activation-test"}
    }

    snapshot = %Snapshot{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      lifecycle: :open,
      created_by_actor_id: "actor-test",
      created_by_command_id: "command-create"
    }

    state =
      recorder
      |> State.new(snapshot, %{})
      |> Map.put(:connections, %{
        "connection-test" => %{
          participant_id: "human-test",
          pid: self(),
          output_sink: nil
        }
      })
      |> Map.put(:text_capability, %{
        module: :test_text_capability,
        monitor: nil,
        participant_id: "agent-test",
        pid: self()
      })

    assert {:ok, command} =
             SendText.new(
               id: "command-source",
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: "room-test",
               incarnation_id: "incarnation-test",
               participant_id: "human-test",
               connection_id: "connection-test",
               correlation_id: "turn-source",
               content: "first request",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    state = TurnState.put(state, command)

    interrupter = %TurnInterrupter{
      participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "command-interruption",
      correlation_id: "turn-interruption"
    }

    assert {:ok, _state} = AgentOutput.interrupt(interrupter, state)

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{
                      command_id: "command-source",
                      interruption_command_id: "command-interruption"
                    }}

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :agent_turn_interrupted,
                      participant_id: "agent-test",
                      activation_id: "activation-test",
                      command_id: "command-source",
                      correlation_id: "turn-source",
                      public_sequence: 1
                    }}
  end

  test "discarded speech settles its segment without recording unheard words" do
    snapshot = %Snapshot{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      lifecycle: :open,
      created_by_actor_id: "actor-test",
      created_by_command_id: "create"
    }

    {:ok, command} =
      SendText.new(
        id: "old",
        tenant_id: "tenant-test",
        actor_id: "actor-test",
        room_id: "room-test",
        incarnation_id: "incarnation-test",
        participant_id: "human-test",
        connection_id: "connection-test",
        correlation_id: "old-turn",
        content: "hello",
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    replacement = %{command | id: "new", correlation_id: "new-turn"}
    state = State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})

    state = %{
      state
      | connections: %{
          "connection-test" => %{
            participant_id: "human-test",
            pid: self(),
            output_sink: self()
          }
        },
        text_to_speech_capability: %{pid: self()}
    }

    state = state |> TurnState.put(command) |> TurnState.put(replacement)
    state = TurnState.update(state, command, &%{&1 | pending_speech: 1})

    request = %Vxpipe.CallEngine.TextToSpeechRequest{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-test",
      source_participant_id: "human-test",
      connection_id: "connection-test",
      command_id: "old",
      correlation_id: "old-turn",
      output_id: "output-old",
      text: "Unheard words",
      output_sink: self()
    }

    settled = AgentOutput.playback(self(), request, :discarded, state)
    assert TurnState.get(settled, command).pending_speech == 0
    assert TurnState.active?(settled, command)
    assert TurnState.get(settled, replacement) == TurnState.get(state, replacement)
    assert settled.spoken_history == state.spoken_history
    assert settled.archive_recorder == state.archive_recorder
    refute_receive {:vxpipe_event, _event}

    finished = TurnState.update(state, command, &%{&1 | generation_complete?: true})
    settled = AgentOutput.playback(self(), request, :discarded, finished)
    refute TurnState.active?(settled, command)
    assert TurnState.active?(settled, replacement)
    assert settled.spoken_history == state.spoken_history
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.AgentTurnCompleted{command_id: "old"}}
    assert AgentOutput.playback(self(), request, :discarded, settled) == settled
    refute_receive {:vxpipe_event, _event}
  end

  defp open_archive do
    assert {:ok, handoff} =
             ArchiveSupervisor.open(
               writer: {TestCollectingArchiveWriter, self()},
               maximum_pending_facts: 8,
               retry_delay_ms: 5,
               drain_timeout_ms: 1_000
             )

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end
end
