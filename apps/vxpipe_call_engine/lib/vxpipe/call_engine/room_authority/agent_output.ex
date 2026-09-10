defmodule Vxpipe.CallEngine.RoomAuthority.AgentOutput do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder
  alias Vxpipe.CallEngine.Capability.{ModelInference, TextToSpeech}
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}

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
    ConnectionLifecycle,
    EventPublisher,
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

    if TurnState.active?(state, command) and
         TextCapability.current?(state, capability) and
         connection != nil and
         connection.participant_id == command.participant_id do
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
        aggregated_by: :sentence,
        will_be_spoken: will_be_spoken,
        occurred_at: occurred_at
      }

      state = EventPublisher.publish(state, connection.pid, output)
      state = %{state | next_sequence: state.next_sequence + 1}

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
          output_sink: connection.output_sink
        }

        case TextToSpeech.synthesize(state.text_to_speech_capability.pid, request) do
          :ok ->
            TurnState.update(state, command, fn turn ->
              %{turn | pending_speech: turn.pending_speech + 1}
            end)

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

  @spec failed(pid(), struct(), term(), State.t()) :: State.t()
  def failed(capability, command, reason, %State{} = state) do
    connection = Map.get(state.connections, command.connection_id)

    if TurnState.active?(state, command) and
         TextCapability.current?(state, capability) and
         connection != nil and connection.participant_id == command.participant_id do
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

      state = EventPublisher.publish(state, connection.pid, event)

      state
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> TurnState.delete(command)
    else
      state
    end
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
      end
    else
      state
    end
  end

  @spec text_complete(pid(), struct(), State.t()) :: State.t()
  def text_complete(capability, command, %State{} = state) do
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
  def interrupt(%SendText{run_immediately: false}, %State{} = state), do: {:ok, state}

  def interrupt(%SendText{} = command, %State{} = state) do
    interrupter = %TurnInterrupter{
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id
    }

    interrupt(interrupter, state)
  end

  def interrupt(%TurnInterrupter{}, %State{agent_turns: agent_turns} = state)
      when map_size(agent_turns) == 0,
      do: {:ok, state}

  def interrupt(%TurnInterrupter{} = interrupter, %State{} = state) do
    turns = state.agent_turns |> Map.values() |> Enum.sort_by(& &1.order, :desc)
    turn_ids = Enum.map(turns, &TurnState.key(&1.command))

    with {:ok, speech_requests} <- interrupt_text_to_speech(state),
         {:ok, _commands} <- interrupt_text_generation(state, turn_ids) do
      played_by_turn =
        Map.new(speech_requests, fn {request, played_ms} ->
          {TurnState.key(request), played_ms}
        end)

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

  @spec failure_reason(term()) ::
          :invalid_response | :provider_timeout | :provider_unavailable
  def failure_reason(reason)
      when reason in [:invalid_response, :provider_timeout, :provider_unavailable],
      do: reason

  def failure_reason(_reason), do: :provider_unavailable

  defp authorized_text_to_speech?(capability, request, connection, state) do
    TurnState.active?(state, request) and state.text_to_speech_capability != nil and
      state.text_to_speech_capability.pid == capability and connection != nil and
      connection.output_sink == request.output_sink and
      connection.participant_id == request.source_participant_id and
      state.snapshot.tenant_id == request.tenant_id and state.snapshot.room_id == request.room_id and
      state.snapshot.incarnation_id == request.incarnation_id
  end

  defp emit_speech_started(request, connection, state) do
    event = struct!(AgentSpeechStarted, event_fields(request, state))

    state =
      EventPublisher.publish(state, connection.pid, event,
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
        payload: %{"output_id" => request.output_id, "text" => request.text}
      )

    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_turn_completed(%TextToSpeechRequest{} = request, connection, state) do
    event = struct!(AgentTurnCompleted, event_fields(request, state))
    state = EventPublisher.publish(state, connection.pid, event)

    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> TurnState.delete(request)
  end

  defp emit_turn_completed(command, connection, occurred_at, state) do
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
  end

  defp complete_spoken_segment(request, connection, state) do
    archive_recorder = ArchiveRecorder.delivered_output(state.archive_recorder, request)
    state = %{state | archive_recorder: archive_recorder}
    turn = TurnState.get(state, request)
    turn = %{turn | pending_speech: max(turn.pending_speech - 1, 0)}
    state = TurnState.replace(state, request, turn)

    if turn.generation_complete? and turn.pending_speech == 0 do
      emit_turn_completed(request, connection, state)
    else
      state
    end
  end

  defp interrupt_text_to_speech(%{text_to_speech_capability: nil}), do: {:ok, []}

  defp interrupt_text_to_speech(state) do
    TextToSpeech.interrupt(state.text_to_speech_capability.pid)
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
