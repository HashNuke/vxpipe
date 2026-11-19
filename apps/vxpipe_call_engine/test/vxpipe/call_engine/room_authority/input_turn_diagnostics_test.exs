defmodule Vxpipe.CallEngine.RoomAuthority.InputTurnDiagnosticsTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Event.{ParticipantTurnStarted, ParticipantTurnCompleted}
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

  setup do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :settings)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :settings
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)
    {:ok, handoff} = CaptureHandoff.new(self(), projection: __MODULE__.Projection)
    %{handoff: handoff}
  end

  test "accepted completion links exact allocation and turn refs to room IDs without response text",
       ctx do
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    state = InputTurns.speech_to_text(self(), @identity, signal, state(self()))

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{correlation_id: turn, command_id: command}}

    before = System.monotonic_time(:microsecond)
    ended = %{signal | kind: :turn_ended, provider_sequence: 2}

    assert {:noreply, next} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(
               {:vxpipe_stt_signal, self(), @identity, ended, ctx.handoff},
               state
             )

    after_completion = System.monotonic_time(:microsecond)
    assert next.connections[@identity.connection_id].speech_to_text.turn == nil

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{correlation_id: ^turn, command_id: ^command}}

    assert_receive {:vxpipe_diagnostic_capture, _, _, packet, _} = message
    assert {:room_turn_completed, generation, reference, ^turn, ^command, at} = packet
    assert generation == signal.allocation_generation
    assert reference == signal.turn_ref
    assert at >= before and at <= after_completion
    assert {:ok, ^packet, charge} = CaptureHandoff.message(ctx.handoff, message)
    CaptureHandoff.release(ctx.handoff, charge, :processed)
    assert ^next = InputTurns.speech_to_text(self(), @identity, ended, next, ctx.handoff)
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "stale turn, wrong identity and revoked capture do not publish room evidence", ctx do
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    state = InputTurns.speech_to_text(self(), @identity, signal, state(self()))
    ended = %{signal | kind: :turn_ended, provider_sequence: 2}

    assert ^state =
             InputTurns.speech_to_text(
               self(),
               @identity,
               %{ended | turn_ref: make_ref()},
               state,
               ctx.handoff
             )

    assert ^state =
             InputTurns.speech_to_text(
               self(),
               %{@identity | tenant_id: "other"},
               ended,
               state,
               ctx.handoff
             )

    CaptureHandoff.close(ctx.handoff)
    next = InputTurns.speech_to_text(self(), @identity, ended, state, ctx.handoff)
    assert next.connections[@identity.connection_id].speech_to_text.turn == nil
    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
  end

  test "saturation cannot prevent normal completion", _ctx do
    {:ok, handoff} =
      CaptureHandoff.new(self(), projection: __MODULE__.Projection, maximum_count: 1)

    assert :ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0})
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    state = InputTurns.speech_to_text(self(), @identity, signal, state(self()))

    next =
      InputTurns.speech_to_text(self(), @identity, %{signal | kind: :turn_ended}, state, handoff)

    assert next.connections[@identity.connection_id].speech_to_text.turn == nil
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
    assert %{overflow: 1, pending_count: 1} = CaptureHandoff.stats(handoff)
  end

  test "unowned capture and a room without an LLM never receive evidence", ctx do
    {:ok, unowned} =
      CaptureHandoff.new(self(), projection: __MODULE__.Projection, owner: Process.whereis(:init))

    for {handoff, current} <- [
          {unowned, state(self())},
          {ctx.handoff, %{state(self()) | text_capability: nil}}
        ] do
      signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
      current = InputTurns.speech_to_text(self(), @identity, signal, current)

      next =
        InputTurns.speech_to_text(
          self(),
          @identity,
          %{signal | kind: :turn_ended},
          current,
          handoff
        )

      assert next.connections[@identity.connection_id].speech_to_text.turn == nil
    end

    refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
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

    %{
      state
      | text_capability: %{module: Vxpipe.CallEngine.AgentRuntime.Coordinator},
        connections: %{@identity.connection_id => connection}
    }
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
