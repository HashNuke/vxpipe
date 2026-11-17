defmodule Vxpipe.CallEngine.RoomAuthority.AgentModeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{State, TurnState}

  test "mode follows admitted output and matching settlement, not pending inference" do
    state = state()
    first = command("first")
    second = command("second")
    state = TurnState.put(state, first)
    assert TurnState.mode(state) == :listener

    state = TurnState.admit_output(state, first)
    assert TurnState.mode(state) == :speaker

    state = TurnState.put(state, second)
    state = TurnState.delete(state, first)
    assert TurnState.mode(state) == :listener

    state = TurnState.admit_output(state, second)
    assert TurnState.mode(state) == :speaker

    # A late callback for the settled first output cannot change the second.
    state = TurnState.admit_output(state, first)
    state = TurnState.delete(state, first)
    assert TurnState.mode(state) == :speaker
    assert TurnState.mode(TurnState.delete(state, second)) == :listener
  end

  test "detachment retires only its output and a late callback cannot readmit it" do
    first = command("detached")
    second = %{command("connected") | connection_id: "other-connection"}

    state =
      state()
      |> TurnState.put(first)
      |> TurnState.admit_output(first)
      |> TurnState.put(second)
      |> TurnState.admit_output(second)
      |> TurnState.retire_connection_output(first.connection_id)

    assert TurnState.mode(state) == :speaker
    assert TurnState.active?(state, first)
    refute TurnState.output_eligible?(state, first)
    assert TurnState.output_eligible?(state, second)
    state = TurnState.delete(state, second)
    assert TurnState.mode(state) == :listener
    assert TurnState.mode(TurnState.admit_output(state, first)) == :listener
  end

  test "speech targets retain exact generations and settle only their matching request once" do
    command = command("speech-target")

    first = %Vxpipe.CallEngine.TextToSpeechRequest{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: "agent",
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      output_id: "first-output",
      text: "First",
      output_sink: self(),
      output_generation: 1
    }

    second = %{first | output_id: "second-output", text: "Second"}

    state =
      state()
      |> TurnState.put(command)
      |> TurnState.begin_speech(first)
      |> TurnState.begin_speech(second)

    assert TurnState.get(state, command).pending_speech == 2
    assert MapSet.new(TurnState.speech_targets(state, command)) == MapSet.new([first, second])
    assert :stale = TurnState.finish_speech(state, %{first | output_generation: 2})
    assert {:ok, state} = TurnState.finish_speech(state, first)
    assert TurnState.speech_targets(state, command) == [second]
    assert TurnState.get(state, command).pending_speech == 1
    assert :stale = TurnState.finish_speech(state, first)
    assert {:ok, state} = TurnState.finish_speech(state, second)
    assert TurnState.speech_targets(state, command) == []
    assert TurnState.get(state, command).pending_speech == 0
  end

  test "idle selects older completed-generation output and rejects a newer turn" do
    old = command("old")
    origin = command("idle-origin")
    newer = command("newer")
    state = state() |> TurnState.put(old) |> TurnState.admit_output(old)
    state = TurnState.update(state, old, &%{&1 | generation_complete?: true})
    state = %{state | next_sequence: 2} |> TurnState.put(origin)
    assert {:ok, [target]} = TurnState.idle_targets(state, origin)
    assert target.command == old

    assert {:ok, retired} =
             Vxpipe.CallEngine.RoomAuthority.AgentOutput.interrupt_idle(origin, state)

    refute TurnState.active?(retired, old)
    assert TurnState.active?(retired, origin)
    assert {:ok, []} = TurnState.idle_targets(TurnState.delete(state, old), origin)
    assert {:error, :stale} = TurnState.idle_targets(TurnState.delete(state, origin), origin)
    newer_state = %{state | next_sequence: 3} |> TurnState.put(newer)
    assert {:error, :stale} = TurnState.idle_targets(newer_state, origin)

    assert {:error, :stale} =
             Vxpipe.CallEngine.RoomAuthority.AgentOutput.interrupt_idle(origin, newer_state)

    unfinished = TurnState.update(state, old, &%{&1 | generation_complete?: false})
    assert {:error, :stale} = TurnState.idle_targets(unfinished, origin)
  end

  defp state do
    State.new(
      %Recorder{port: nil, participant_activations: %{}},
      %Snapshot{
        tenant_id: "tenant-mode",
        room_id: "room-mode",
        incarnation_id: "incarnation-mode",
        lifecycle: :open,
        created_by_actor_id: "actor-mode",
        created_by_command_id: "command-mode"
      },
      %{}
    )
  end

  defp command(seed) do
    {:ok, command} =
      SendText.new(
        tenant_id: "tenant-mode",
        actor_id: "actor-mode",
        room_id: "room-mode",
        incarnation_id: "incarnation-mode",
        participant_id: "human-mode",
        connection_id: "connection-mode",
        correlation_id: seed,
        content: "hello",
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    command
  end
end
