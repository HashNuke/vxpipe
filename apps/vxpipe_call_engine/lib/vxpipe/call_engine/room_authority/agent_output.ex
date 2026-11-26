defmodule Vxpipe.CallEngine.RoomAuthority.AgentOutput do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder
  alias Vxpipe.CallEngine.Capability.{ModelInference, TextToSpeech}
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.Diagnostics.ResponseTiming

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    TextOutput
  }

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator
  alias Vxpipe.CallEngine.{Id, TextToSpeechRequest, TurnInterrupter}

  alias Vxpipe.CallEngine.RoomAuthority.{
    CallerAnswer,
    ConnectionLifecycle,
    EventPublisher,
    FirstMessage,
    IdleWait,
    OutputHistory,
    SpeechToSpeech,
    State,
    TextCapability,
    ToolCalls,
    TurnState
  }

  @spec continuation_started(pid(), ContinueAgent.t(), State.t()) :: State.t()
  def continuation_started(capability, %ContinueAgent{} = command, %State{} = state) do
    if authorized_continuation?(capability, command, state) do
      TurnState.put(state, command)
    else
      state
    end
  end

  @spec text(pid(), struct(), String.t(), State.t()) :: State.t()
  def text(capability, command, text, %State{} = state) do
    connection = Map.get(state.connections, command.connection_id)

    if deliver_text?(capability, command, connection, text, state) do
      occurred_at = DateTime.utc_now(:millisecond)

      will_be_spoken =
        command.audio_response and state.text_to_speech_capability != nil and
          is_pid(connection.output_sink)

      output = %TextOutput{
        id: Id.generate(:event),
        sequence: state.next_sequence,
        tenant_id: state.snapshot.tenant_id,
        room_id: state.snapshot.room_id,
        incarnation_id: state.snapshot.incarnation_id,
        participant_id: state.text_capability.participant_id,
        source_participant_id: command.participant_id,
        connection_id: command.connection_id,
        command_id: command.id,
        correlation_id: command.correlation_id,
        text: text,
        agent_mode: :speaker,
        aggregated_by: :sentence,
        will_be_spoken: will_be_spoken,
        occurred_at: occurred_at
      }

      {state, source_policy, recipients} =
        EventPublisher.publish_transcript_with_recipients(state, connection.pid, output)

      state =
        if text != "" and (recipients == :legacy or MapSet.size(recipients) > 0),
          do: ResponseTiming.observe(state, command, output.id, :first_response_text),
          else: state

      state = %{state | next_sequence: state.next_sequence + 1}
      state = TurnState.admit_output(state, command)

      state =
        if not will_be_spoken and
             (not command.audio_response or
                (state.text_to_speech_runtime == nil and state.text_to_speech_capability == nil)),
           do: OutputHistory.confirm(state, command, output.id, text),
           else: state

      if will_be_spoken do
        request = %TextToSpeechRequest{
          tenant_id: state.snapshot.tenant_id,
          room_id: state.snapshot.room_id,
          incarnation_id: state.snapshot.incarnation_id,
          participant_id: state.text_to_speech_capability.participant_id,
          source_participant_id: command.participant_id,
          connection_id: command.connection_id,
          command_id: command.id,
          correlation_id: command.correlation_id,
          output_id: output.id,
          text: text,
          output_sink: connection.output_sink,
          output_generation: Map.get(connection, :output_generation, 0),
          source_policy: source_policy
        }

        case TextToSpeech.synthesize(state.text_to_speech_capability.pid, request) do
          :ok ->
            TurnState.begin_speech(state, request)

          {:error, _reason} ->
            send(connection.pid, {:vxpipe_connection_unavailable, :text_to_speech_unavailable})
            state
        end
      else
        state
      end
    else
      state
    end
  end

  defp deliver_text?(capability, command, connection, text, state) do
    TurnState.active?(state, command) and TurnState.output_eligible?(state, command) and
      IdleWait.output_allowed?(state, capability, command) and
      not State.conversation_held?(state, command.participant_id) and
      TextCapability.current?(state, capability) and
      connection != nil and
      CallerAnswer.output_allowed?(command, connection, state.text_capability.pid, text) and
      connection.participant_id == command.participant_id
  end

  @spec failed(pid(), struct(), term(), State.t()) :: State.t()
  def failed(capability, command, reason, %State{} = state) do
    state = IdleWait.acknowledgment_failed(capability, command, state)

    cond do
      retired_current?(state, capability, command) -> settle_retired(state, command)
      untracked_current?(state, capability, command) -> settle_untracked(state, command)
      true -> fail_connected(capability, command, reason, state)
    end
  end

  defp fail_connected(capability, command, reason, state) do
    connection = Map.get(state.connections, command.connection_id)

    if TurnState.active?(state, command) and
         TextCapability.current?(state, capability) and
         connection != nil and connection.participant_id == command.participant_id do
      if TurnState.get(state, command).pending_speech == 0 do
        emit_turn_failed(command, reason, connection, state)
      else
        TurnState.update(
          state,
          command,
          &Map.merge(&1, %{generation_complete?: true, failure: reason})
        )
      end
    else
      state
    end
  end

  defp emit_turn_failed(command, reason, connection, state) do
    event = %AgentTurnFailed{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: state.text_capability.participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      reason: failure_reason(reason),
      retryable: true,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    _ = OutputHistory.settle(state, command)
    state = EventPublisher.publish(state, connection.pid, event)

    # A failed opening releases its protection like a completed one; otherwise the
    # caller's queued turns would wait for the rest of the call.
    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> TurnState.delete(command)
    |> FirstMessage.complete(command)
  end

  @spec playback(pid(), TextToSpeechRequest.t(), term(), State.t()) :: State.t()
  def playback(capability, %TextToSpeechRequest{} = request, status, %State{} = state) do
    connection = Map.get(state.connections, request.connection_id)

    if authorized_text_to_speech?(capability, request, connection, state) do
      case status do
        :started ->
          emit_speech_started(request, connection, state)

        {:progress, played_ms, total_ms} ->
          emit_speech_progressed(request, connection, played_ms, total_ms, state)

        :completed ->
          complete_spoken_segment(request, connection, state)

        :discarded ->
          settle_speech_segment(request, connection, state)
      end
    else
      state
    end
  end

  @spec text_complete(pid(), struct(), State.t()) :: State.t()
  def text_complete(capability, command, %State{} = state) do
    cond do
      retired_current?(state, capability, command) -> settle_retired(state, command)
      untracked_current?(state, capability, command) -> settle_untracked(state, command)
      true -> complete_connected(capability, command, state)
    end
  end

  defp complete_connected(capability, command, state) do
    connection = Map.get(state.connections, command.connection_id)

    if TurnState.active?(state, command) and
         TextCapability.current?(state, capability) and connection != nil and
         connection.participant_id == command.participant_id do
      turn = TurnState.get(state, command)

      if turn.pending_speech == 0 do
        emit_turn_completed(command, connection, DateTime.utc_now(:millisecond), state)
      else
        TurnState.update(state, command, &%{&1 | generation_complete?: true})
      end
    else
      state
    end
  end

  @spec interrupt(SendText.t() | TurnInterrupter.t(), State.t()) ::
          {:ok, State.t()} | {:error, term()}
  def interrupt(command, state), do: interrupt(command, state, nil)

  def interrupt(%SendText{run_immediately: false}, %State{} = state, _observation),
    do: {:ok, state}

  def interrupt(%SendText{} = command, %State{} = state, observation) do
    interrupter = %TurnInterrupter{
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id
    }

    interrupt(interrupter, state, observation)
  end

  def interrupt(%TurnInterrupter{}, %State{agent_turns: agent_turns} = state, _observation)
      when map_size(agent_turns) == 0,
      do: {:ok, state}

  def interrupt(%TurnInterrupter{} = interrupter, %State{} = state, observation) do
    if FirstMessage.playing?(state) do
      {:ok, state}
    else
      interrupt_active(interrupter, state, observation)
    end
  end

  defp interrupt_active(interrupter, state, observation) do
    turns = state.agent_turns |> Map.values() |> Enum.sort_by(& &1.order, :desc)
    turn_ids = Enum.map(turns, &TurnState.key(&1.command))

    with {:ok, speech_requests} <- interrupt_text_to_speech(state, observation),
         {:ok, _commands} <- interrupt_text_generation(state, turn_ids),
         {:ok, state} <- interrupt_speech_to_speech(state) do
      Enum.each(turns, &OutputHistory.settle(state, &1.command))

      played_by_turn = played_by_turn(speech_requests)

      state = %{state | agent_turns: %{}}

      state =
        Enum.reduce(turns, state, fn turn, state ->
          state = ToolCalls.cancel_active(state, turn)

          emit_turn_interrupted(
            turn.command,
            interrupter,
            Map.get(played_by_turn, TurnState.key(turn.command), 0),
            state
          )
        end)

      {:ok, state}
    end
  end

  def retire_source(
        %State{text_capability: %{module: AgentRuntimeCoordinator} = capability} = state,
        participant_id
      )
      when capability.participant_id != participant_id do
    turns =
      Enum.filter(Map.values(state.agent_turns), &(&1.command.participant_id == participant_id))

    retire_turns(turns, state, capability.pid, participant_id)
  end

  def retire_source(state, _participant_id), do: state

  defp retire_turns([], state, _coordinator, _participant_id), do: state

  defp retire_turns(turns, state, coordinator, participant_id) do
    requests = Enum.flat_map(turns, &TurnState.speech_targets(state, &1.command))
    _ = interrupt_selected_speech(state, requests)

    case AgentRuntimeCoordinator.retire_source(coordinator, participant_id) do
      :ok ->
        Enum.reduce(turns, state, fn turn, acc ->
          _ = OutputHistory.settle(acc, turn.command)
          acc |> TurnState.delete(turn.command) |> FirstMessage.complete(turn.command)
        end)

      {:error, :unavailable} ->
        # The activation may already be shutting down during transfer. Its
        # monitor owns that lifecycle. Invalidate output for the draining source.
        Enum.reduce(turns, state, fn turn, acc ->
          TurnState.retire_connection_output(acc, turn.command.connection_id)
        end)
    end
  end

  @spec unavailable(pid(), State.t()) :: State.t()
  def unavailable(capability, %State{} = state) do
    if state.text_to_speech_capability != nil and
         state.text_to_speech_capability.pid == capability do
      Process.demonitor(state.text_to_speech_capability.monitor, [:flush])
      ConnectionLifecycle.notify(state.connections, :agent_unavailable)
      %{state | text_to_speech_capability: nil}
    else
      state
    end
  end

  def interrupt_idle(context, state) do
    with {:ok, turns} <- TurnState.idle_targets(state, context),
         requests = Enum.flat_map(turns, &TurnState.speech_targets(state, &1.command)),
         {:ok, interrupted} <- interrupt_selected_speech(state, requests) do
      played = played_by_turn(interrupted)

      interrupter = %TurnInterrupter{
        participant_id:
          Map.get(context, :source_participant_id) || Map.get(context, :participant_id),
        connection_id: context.connection_id,
        command_id: Map.get(context, :command_id) || Map.get(context, :id),
        correlation_id: context.correlation_id
      }

      state =
        Enum.reduce(turns, state, fn turn, acc ->
          _ = OutputHistory.settle(acc, turn.command)
          acc = TurnState.delete(acc, turn.command)

          emit_turn_interrupted(
            turn.command,
            interrupter,
            Map.get(played, TurnState.key(turn.command), 0),
            acc
          )
        end)

      {:ok, state}
    end
  end

  defp played_by_turn(requests) do
    Enum.reduce(requests, %{}, fn {request, played_ms}, acc ->
      Map.update(acc, TurnState.key(request), played_ms, &(&1 + played_ms))
    end)
  end

  defp interrupt_selected_speech(_state, []), do: {:ok, []}

  defp interrupt_selected_speech(%{text_to_speech_capability: nil}, _requests),
    do: {:error, :unavailable}

  defp interrupt_selected_speech(state, requests),
    do: TextToSpeech.interrupt(state.text_to_speech_capability.pid, requests)

  @spec failure_reason(term()) ::
          :invalid_response | :provider_timeout | :provider_unavailable
  def failure_reason(reason)
      when reason in [:invalid_response, :provider_timeout, :provider_unavailable],
      do: reason

  def failure_reason(_reason), do: :provider_unavailable

  defp authorized_text_to_speech?(capability, request, connection, state) do
    TurnState.active?(state, request) and state.text_to_speech_capability != nil and
      request in TurnState.speech_targets(state, request) and
      state.text_to_speech_capability.pid == capability and connection != nil and
      connection.output_sink == request.output_sink and
      connection.participant_id == request.source_participant_id and
      state.snapshot.tenant_id == request.tenant_id and state.snapshot.room_id == request.room_id and
      state.snapshot.incarnation_id == request.incarnation_id
  end

  defp emit_speech_started(request, connection, state) do
    state = ResponseTiming.observe(state, request, request.output_id, :first_audio_start)
    event = struct!(AgentSpeechStarted, event_fields(request, state))

    state =
      EventPublisher.publish(state, connection.pid, event,
        source_policy: request.source_policy,
        payload: %{"output_id" => request.output_id, "text" => request.text}
      )

    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_speech_progressed(request, connection, played_ms, total_ms, state) do
    event =
      struct!(
        AgentSpeechProgressed,
        Map.merge(event_fields(request, state), %{played_ms: played_ms, total_ms: total_ms})
      )

    state =
      EventPublisher.publish(state, connection.pid, event,
        source_policy: request.source_policy,
        payload: %{"output_id" => request.output_id, "text" => request.text}
      )

    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_turn_completed(%TextToSpeechRequest{} = request, connection, state) do
    _ = OutputHistory.settle(state, request)
    event = struct!(AgentTurnCompleted, event_fields(request, state))
    state = EventPublisher.publish(state, connection.pid, event)

    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> TurnState.delete(request)
    |> FirstMessage.complete(request)
  end

  defp emit_turn_completed(command, connection, occurred_at, state) do
    _ = OutputHistory.settle(state, command)

    event = %AgentTurnCompleted{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: state.text_capability.participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      occurred_at: occurred_at
    }

    state = EventPublisher.publish(state, connection.pid, event)

    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> TurnState.delete(command)
    |> FirstMessage.complete(command)
  end

  defp complete_spoken_segment(request, connection, state) do
    archive_recorder = ArchiveRecorder.delivered_output(state.archive_recorder, request)

    state = %{state | archive_recorder: archive_recorder}
    state = OutputHistory.confirm(state, request, request.output_id, request.text)
    settle_speech_segment(request, connection, state)
  end

  defp settle_speech_segment(request, connection, state) do
    case TurnState.finish_speech(state, request) do
      {:ok, state} ->
        turn = TurnState.get(state, request)

        case turn do
          %{pending_speech: 0, failure: reason} ->
            emit_turn_failed(turn.command, reason, connection, state)

          %{pending_speech: 0, generation_complete?: true} ->
            emit_turn_completed(request, connection, state)

          _pending ->
            state
        end

      :stale ->
        state
    end
  end

  defp retired_current?(state, capability, command) do
    TurnState.active?(state, command) and not TurnState.output_eligible?(state, command) and
      TextCapability.current?(state, capability)
  end

  defp untracked_current?(state, capability, command),
    do: not TurnState.active?(state, command) and TextCapability.current?(state, capability)

  defp settle_untracked(state, command) do
    _ = OutputHistory.settle_untracked(state, command)
    state
  end

  defp settle_retired(state, command) do
    _ = OutputHistory.settle(state, command)
    state |> TurnState.delete(command) |> FirstMessage.complete(command)
  end

  defp interrupt_text_to_speech(%{text_to_speech_capability: nil}, _observation), do: {:ok, []}

  defp interrupt_text_to_speech(state, nil) do
    TextToSpeech.interrupt(state.text_to_speech_capability.pid)
  end

  defp interrupt_text_to_speech(state, observation) do
    TextToSpeech.interrupt_observed(state.text_to_speech_capability.pid, observation)
  end

  defp interrupt_speech_to_speech(%{speech_to_speech_capability: nil} = state), do: {:ok, state}

  defp interrupt_speech_to_speech(state) do
    case SpeechToSpeech.interrupt(state) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} -> {:ok, state}
    end
  end

  defp interrupt_text_generation(%{text_capability: %{module: ModelInference}} = state, ids) do
    ModelInference.interrupt(state.text_capability.pid, ids)
  end

  defp interrupt_text_generation(
         %{text_capability: %{module: AgentRuntimeCoordinator}} = state,
         ids
       ) do
    AgentRuntimeCoordinator.interrupt(state.text_capability.pid, ids)
  end

  defp interrupt_text_generation(_state, _ids), do: {:ok, []}

  defp emit_turn_interrupted(command, interrupter, played_ms, state) do
    connection = Map.get(state.connections, command.connection_id)

    if connection != nil and connection.participant_id == command.participant_id do
      event = %AgentTurnInterrupted{
        id: Id.generate(:event),
        sequence: state.next_sequence,
        tenant_id: state.snapshot.tenant_id,
        room_id: state.snapshot.room_id,
        incarnation_id: state.snapshot.incarnation_id,
        participant_id: state.text_capability.participant_id,
        source_participant_id: command.participant_id,
        connection_id: command.connection_id,
        command_id: command.id,
        correlation_id: command.correlation_id,
        interrupted_by_participant_id: interrupter.participant_id,
        interrupted_by_connection_id: interrupter.connection_id,
        interruption_command_id: interrupter.command_id,
        interruption_correlation_id: interrupter.correlation_id,
        played_ms: played_ms,
        occurred_at: DateTime.utc_now(:millisecond)
      }

      state = EventPublisher.publish(state, connection.pid, event)
      %{state | next_sequence: state.next_sequence + 1}
    else
      state
    end
  end

  defp authorized_continuation?(capability, command, state) do
    connection = Map.get(state.connections, command.connection_id)

    TextCapability.current?(state, capability) and connection != nil and
      MapSet.member?(state.participant_ids, command.participant_id) and
      connection.participant_id == command.participant_id and
      command.tenant_id == state.snapshot.tenant_id and command.room_id == state.snapshot.room_id and
      command.incarnation_id == state.snapshot.incarnation_id and
      not TurnState.active?(state, command)
  end

  defp event_fields(request, state) do
    %{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: request.participant_id,
      source_participant_id: request.source_participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      id: Id.generate(:event),
      sequence: state.next_sequence,
      occurred_at: DateTime.utc_now(:millisecond)
    }
  end
end
