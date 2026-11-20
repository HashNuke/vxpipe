defmodule Vxpipe.CallEngine.RoomAuthority.InputTurnDiagnosticsTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Event.{ParticipantTurnStarted, ParticipantTurnCompleted}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{AgentOutput, InputTurns, State, TurnState}
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @identity %{
    tenant_id: "tenant-input-turn",
    room_id: "room-input-turn",
    incarnation_id: "incarnation-input-turn",
    participant_id: "participant-input-turn",
    connection_id: "connection-input-turn"
  }

  setup do
    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

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

  for response_side <- [:none, :sts] do
    @tag response_side: response_side
    test "accepted STT completion is observed with #{response_side} response selection", ctx do
      signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
      initial = %{state(self()) | text_capability: nil}

      initial =
        if ctx.response_side == :sts,
          do: %{initial | speech_to_speech_capability: %{pid: self()}},
          else: initial

      current = InputTurns.speech_to_text(self(), @identity, signal, initial)

      assert_receive {:vxpipe_event,
                      %ParticipantTurnStarted{correlation_id: turn, command_id: command}}

      ended = %{signal | kind: :turn_ended, provider_sequence: 2, text: "Human input"}
      next = InputTurns.speech_to_text(self(), @identity, ended, current, ctx.handoff)

      assert_receive {:vxpipe_event,
                      %ParticipantTurnCompleted{correlation_id: ^turn, command_id: ^command}}

      assert_receive {:vxpipe_diagnostic_capture, _, _,
                      {:room_turn_completed, generation, reference, ^turn, ^command, _}, _}

      assert generation == signal.allocation_generation
      assert reference == signal.turn_ref
      assert next.agent_turns == %{}
      refute_received {:diagnostic_response_command, _}
    end
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
      CaptureHandoff.new(self(),
        settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
        maximum_count: 1
      )

    assert :ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0})
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    state = InputTurns.speech_to_text(self(), @identity, signal, state(self()))

    next =
      InputTurns.speech_to_text(self(), @identity, %{signal | kind: :turn_ended}, state, handoff)

    assert next.connections[@identity.connection_id].speech_to_text.turn == nil
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
    assert %{overflow: 1, pending_count: 1} = CaptureHandoff.stats(handoff)
  end

  test "unowned capture never receives evidence" do
    {:ok, unowned} =
      CaptureHandoff.new(self(),
        settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
        owner: Process.whereis(:init)
      )

    for current <- [state(self()), %{state(self()) | text_capability: nil}] do
      handoff = unowned
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

  test "first published response and acknowledged audio retain the input command identity", ctx do
    {state, command} = response_turn(ctx.handoff)
    before = System.monotonic_time(:microsecond)
    state = AgentOutput.text(self(), command, "first sentence", state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{id: output}}

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:response_landmark, turn, id, ^output, :first_response_text, at}, _}

    assert turn == command.correlation_id and id == command.id
    assert at >= before and at <= System.monotonic_time(:microsecond)
    state = AgentOutput.text(self(), command, "second sentence", state)
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}

    request = %TextToSpeechRequest{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: "agent",
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      output_id: output,
      text: "first sentence",
      output_sink: self()
    }

    state = put_in(state.connections[command.connection_id].output_sink, self())
    state = %{state | text_to_speech_capability: %{pid: self(), participant_id: "agent"}}
    state = TurnState.begin_speech(state, request)
    before = System.monotonic_time(:microsecond)
    state = AgentOutput.playback(self(), request, :started, state)

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:response_landmark, ^turn, ^id, ^output, :first_audio_start, at}, _}

    assert at >= before and at <= System.monotonic_time(:microsecond)
    _ = AgentOutput.playback(self(), request, :started, state)
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
  end

  test "empty text does not consume the first response landmark", ctx do
    {state, command} = response_turn(ctx.handoff)
    state = AgentOutput.text(self(), command, "", state)
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
    _ = AgentOutput.text(self(), command, "actual response", state)

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:response_landmark, _, _, _, :first_response_text, _}, _}
  end

  test "revoked capture cannot suppress response delivery or observe a later output", ctx do
    {state, command} = response_turn(ctx.handoff)
    CaptureHandoff.close(ctx.handoff)
    _ = AgentOutput.text(self(), command, "still delivered", state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{text: "still delivered"}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
  end

  test "unrelated commands do not inherit the observed input", ctx do
    {state, command} = response_turn(ctx.handoff)
    other = %{command | id: "unrelated-command", correlation_id: "other-turn"}
    state = TurnState.put(state, other)
    _ = AgentOutput.text(self(), other, "unrelated", state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{text: "unrelated"}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
  end

  for response <- [:silent, :tool_only] do
    @response response
    test "#{@response} completion does not invent text or audio landmarks", ctx do
      {state, command} = response_turn(ctx.handoff)

      state =
        if @response == :tool_only do
          call = %Vxpipe.CallEngine.Tool.Call{id: "lookup", name: "lookup", arguments: %{}}
          next = Vxpipe.CallEngine.RoomAuthority.ToolCalls.started(state, self(), command, call)
          assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{}}

          next =
            Vxpipe.CallEngine.RoomAuthority.ToolCalls.completed(next, self(), command, call, %{})

          assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCompleted{}}
          next
        else
          state
        end

      next = AgentOutput.text_complete(self(), command, state)
      assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.AgentTurnCompleted{}}
      assert TurnState.get(next, command) == nil
      refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
    end
  end

  test "a replaced text capability cannot contribute another agent's first response", ctx do
    {state, command} = response_turn(ctx.handoff)
    replacement = start_supervised!({Agent, fn -> nil end})

    routed = %{
      state
      | text_capability: %{
          module: __MODULE__,
          pid: replacement,
          participant_id: "replacement-agent"
        }
    }

    assert ^routed = AgentOutput.text(self(), command, "retired agent", routed)
    refute_received {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}

    _ = AgentOutput.text(replacement, command, "routed response", routed)

    assert_receive {:vxpipe_event,
                    %Vxpipe.CallEngine.Event.TextOutput{
                      id: output,
                      participant_id: "replacement-agent",
                      text: "routed response"
                    }}

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:response_landmark, turn, id, ^output, :first_response_text, _}, _}

    assert turn == command.correlation_id
    assert id == command.id
  end

  test "audio onset carries its own observation and new turn identity into interruption", ctx do
    {current, _old_command} = response_turn(ctx.handoff)
    parent = self()

    speech =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", from, message} ->
               send(parent, {:interruption_request, message})
               GenServer.reply(from, {:ok, []})
           end
         end}
      )

    current = %{current | text_to_speech_capability: %{pid: speech, participant_id: "agent"}}
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    next = InputTurns.speech_to_text(self(), @identity, signal, current, ctx.handoff)
    turn = next.connections[@identity.connection_id].speech_to_text.turn
    generation = signal.allocation_generation
    reference = signal.turn_ref
    handoff = ctx.handoff
    new_turn = turn.id
    command = turn.command_id

    assert_receive {:interruption_request,
                    {:interrupt_observed,
                     {^handoff, ^generation, ^reference, ^new_turn, ^command}}}

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:room_turn_started, ^generation, ^reference, ^new_turn, ^command, _}, _}
  end

  test "failed interruption does not invent an accepted human turn for diagnostics", ctx do
    {current, old_command} = response_turn(ctx.handoff)
    old_turn = old_command.correlation_id
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: ^old_turn}}

    speech =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", from, {:interrupt_observed, _}} ->
               GenServer.reply(from, {:error, :unavailable})
           end
         end}
      )

    current = %{current | text_to_speech_capability: %{pid: speech, participant_id: "agent"}}
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}
    assert ^current = InputTurns.speech_to_text(self(), @identity, signal, current, ctx.handoff)
    refute_received {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:room_turn_started, _, _, _, _, _}, _}
  end

  test "interruption prevents late text and playback from fabricating a response", ctx do
    {state, command} = response_turn(ctx.handoff)

    interrupter = %Vxpipe.CallEngine.TurnInterrupter{
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: "interrupt",
      correlation_id: "interrupt-turn"
    }

    request = %TextToSpeechRequest{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: "agent",
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      output_id: "late-output",
      text: "late response",
      output_sink: self()
    }

    speech =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", from, :interrupt} -> GenServer.reply(from, {:ok, [{request, 0}]})
           end
         end}
      )

    state = put_in(state.connections[command.connection_id].output_sink, self())
    state = %{state | text_to_speech_capability: %{pid: speech, participant_id: "agent"}}
    state = TurnState.begin_speech(state, request)
    assert TurnState.speech_targets(state, command) == [request]
    assert {:ok, interrupted} = AgentOutput.interrupt(interrupter, state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.AgentTurnInterrupted{}}
    assert TurnState.get(interrupted, command) == nil
    assert ^interrupted = AgentOutput.text(self(), command, "late response", interrupted)
    assert ^interrupted = AgentOutput.playback(speech, request, :started, interrupted)
    refute_received {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{}}
    refute_received {:vxpipe_event, %Vxpipe.CallEngine.Event.AgentSpeechStarted{}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
  end

  test "full diagnostic queues cannot suppress text or relabel a later sentence as first" do
    {:ok, handoff} =
      CaptureHandoff.new(self(),
        settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
        maximum_count: 1
      )

    {state, command} = response_turn(handoff)
    assert :ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0})
    state = AgentOutput.text(self(), command, "first", state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{text: "first"}}
    assert %{overflow: 1} = CaptureHandoff.stats(handoff)
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:reset, _, _, _}, _} = queued
    {:ok, _, charge} = CaptureHandoff.message(handoff, queued)
    CaptureHandoff.release(handoff, charge, :processed)
    _ = AgentOutput.text(self(), command, "second", state)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.TextOutput{text: "second"}}
    refute_received {:vxpipe_diagnostic_capture, _, _, {:response_landmark, _, _, _, _, _}, _}
  end

  def respond(receiver, command) do
    send(receiver, {:diagnostic_response_command, command})
    :ok
  end

  defp response_turn(handoff) do
    signal = %{turn_started(0) | allocation_generation: make_ref(), turn_ref: make_ref()}

    current = %{
      state(self())
      | text_capability: %{module: __MODULE__, pid: self(), participant_id: "agent"}
    }

    current = InputTurns.speech_to_text(self(), @identity, signal, current)

    current =
      InputTurns.speech_to_text(
        self(),
        @identity,
        %{signal | kind: :turn_ended, text: "hello"},
        current,
        handoff
      )

    assert_receive {:diagnostic_response_command, command}

    assert_receive {:vxpipe_diagnostic_capture, _, _, {:room_turn_completed, _, _, _, _, _}, _} =
                     message

    {:ok, _, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
    {current, command}
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
