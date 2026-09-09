defmodule Vxpipe.CallEngine.RoomAuthority.InputTurns do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Error

  alias Vxpipe.CallEngine.Event.{
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted
  }

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.{Id, TurnInterrupter}

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    ConnectionLifecycle,
    EventPublisher,
    State,
    TextCapability,
    TurnState
  }

  @spec accept_text(struct(), pid(), State.t()) ::
          {:reply, :ok | {:error, Error.t()}, State.t()}
  def accept_text(command, caller, %State{} = state) do
    case ConnectionLifecycle.authorize_text(command, caller, state) do
      {:ok, capability} ->
        case AgentOutput.interrupt(command, state) do
          {:ok, state} ->
            case TextCapability.respond(capability, command) do
              :ok ->
                state = state |> TurnState.put(command) |> emit_participant_text_turn(command)
                {:reply, :ok, state}

              {:error, reason} ->
                {:reply, {:error, agent_busy(reason)}, state}
            end

          {:error, reason} ->
            {:reply, {:error, agent_busy(reason)}, state}
        end

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @spec speech_to_text(pid(), map(), Signal.t(), State.t()) :: State.t()
  def speech_to_text(capability, identity, %Signal{} = signal, %State{} = state) do
    case ConnectionLifecycle.authorized_speech_to_text(capability, identity, state) do
      {:ok, connection_id, connection} ->
        apply_speech_to_text_signal(signal, connection_id, connection, state)

      :error ->
        state
    end
  end

  defp apply_speech_to_text_signal(
         %Signal{kind: :turn_started} = signal,
         connection_id,
         connection,
         state
       ) do
    begin_audio_turn(signal, connection_id, connection, state)
  end

  defp apply_speech_to_text_signal(
         %Signal{kind: :transcript_updated} = signal,
         connection_id,
         _connection,
         state
       ) do
    update_audio_transcription(signal, connection_id, state)
  end

  defp apply_speech_to_text_signal(
         %Signal{kind: :turn_ended} = signal,
         connection_id,
         connection,
         state
       ) do
    complete_audio_turn(signal, connection_id, connection, state)
  end

  defp apply_speech_to_text_signal(_signal, _connection_id, _connection, state), do: state

  defp begin_audio_turn(signal, connection_id, connection, state) do
    if connection.speech_to_text.turn == nil and is_binary(signal.text) do
      turn = %{
        command_id: Id.generate(:command),
        id: Id.generate(:turn),
        last_text: signal.text,
        provider_turn_index: signal.provider_turn_index
      }

      case AgentOutput.interrupt(audio_turn_interrupter(turn, connection_id, connection), state) do
        {:ok, state} ->
          started = %ParticipantTurnStarted{
            id: Id.generate(:event),
            sequence: state.next_sequence,
            tenant_id: state.snapshot.tenant_id,
            room_id: state.snapshot.room_id,
            incarnation_id: state.snapshot.incarnation_id,
            participant_id: connection.participant_id,
            connection_id: connection_id,
            command_id: turn.command_id,
            correlation_id: turn.id,
            modality: :audio,
            occurred_at: DateTime.utc_now(:millisecond)
          }

          state = EventPublisher.publish(state, connection.pid, started)

          state =
            state
            |> put_connection_turn(connection_id, turn)
            |> Map.update!(:next_sequence, &(&1 + 1))

          if signal.text == "" do
            state
          else
            emit_participant_transcription(connection_id, turn, signal.text, false, state)
          end

        {:error, _reason} ->
          state
      end
    else
      state
    end
  end

  defp audio_turn_interrupter(turn, connection_id, connection) do
    %TurnInterrupter{
      participant_id: connection.participant_id,
      connection_id: connection_id,
      command_id: turn.command_id,
      correlation_id: turn.id
    }
  end

  defp update_audio_transcription(signal, connection_id, state) do
    connection = Map.fetch!(state.connections, connection_id)
    turn = connection.speech_to_text.turn

    if matching_active_turn?(turn, signal) and is_binary(signal.text) and
         signal.text != turn.last_text do
      turn = %{turn | last_text: signal.text}

      state
      |> put_connection_turn(connection_id, turn)
      |> then(&emit_participant_transcription(connection_id, turn, signal.text, false, &1))
    else
      state
    end
  end

  defp complete_audio_turn(signal, connection_id, connection, state) do
    turn = connection.speech_to_text.turn

    if matching_active_turn?(turn, signal) and is_binary(signal.text) do
      turn = %{turn | last_text: signal.text}

      state =
        state
        |> put_connection_turn(connection_id, turn)
        |> then(&emit_participant_transcription(connection_id, turn, signal.text, true, &1))
        |> emit_participant_audio_turn_completed(connection_id, turn)
        |> put_connection_turn(connection_id, nil)

      dispatch_committed_audio_turn(connection_id, connection, turn, signal.text, state)
    else
      state
    end
  end

  defp emit_participant_transcription(connection_id, turn, text, final, state) do
    connection = Map.fetch!(state.connections, connection_id)

    event = %ParticipantTranscription{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id,
      command_id: turn.command_id,
      correlation_id: turn.id,
      text: text,
      final: final,
      provider_turn_index: turn.provider_turn_index,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    state = EventPublisher.publish(state, connection.pid, event)
    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_participant_audio_turn_completed(state, connection_id, turn) do
    connection = Map.fetch!(state.connections, connection_id)

    event = %ParticipantTurnCompleted{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id,
      command_id: turn.command_id,
      correlation_id: turn.id,
      modality: :audio,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    state = EventPublisher.publish(state, connection.pid, event)
    %{state | next_sequence: state.next_sequence + 1}
  end

  defp dispatch_committed_audio_turn(connection_id, connection, turn, text, state) do
    content = String.trim(text)

    result =
      if content == "" do
        :empty
      else
        SendText.new(
          id: turn.command_id,
          tenant_id: state.snapshot.tenant_id,
          actor_id: connection.actor_id,
          room_id: state.snapshot.room_id,
          incarnation_id: state.snapshot.incarnation_id,
          participant_id: connection.participant_id,
          connection_id: connection_id,
          correlation_id: turn.id,
          content: content,
          run_immediately: false,
          audio_response: true,
          deadline: DateTime.add(DateTime.utc_now(), 5, :second)
        )
      end

    case result do
      {:ok, command} when state.text_capability != nil ->
        case AgentOutput.interrupt(command, state) do
          {:ok, state} ->
            case TextCapability.respond(state.text_capability, command) do
              :ok ->
                archive_recorder =
                  ArchiveRecorder.accepted_input(state.archive_recorder, command, :audio)

                state
                |> Map.put(:archive_recorder, archive_recorder)
                |> TurnState.put(command)

              {:error, reason} ->
                reject_audio_turn(state, command, reason)
            end

          {:error, reason} ->
            reject_audio_turn(state, command, reason)
        end

      _empty_or_invalid ->
        state
    end
  end

  defp reject_audio_turn(state, command, reason) do
    state = TurnState.put(state, command)

    send(
      self(),
      {:vxpipe_capability_failed, state.text_capability.pid, command,
       AgentOutput.failure_reason(reason)}
    )

    state
  end

  defp matching_active_turn?(nil, _signal), do: false

  defp matching_active_turn?(turn, signal) do
    turn.provider_turn_index == signal.provider_turn_index
  end

  defp put_connection_turn(state, connection_id, turn) do
    connection = Map.fetch!(state.connections, connection_id)
    speech_to_text = %{connection.speech_to_text | turn: turn}
    connection = %{connection | speech_to_text: speech_to_text}
    %{state | connections: Map.put(state.connections, connection_id, connection)}
  end

  defp emit_participant_text_turn(state, command) do
    connection = Map.fetch!(state.connections, command.connection_id)
    occurred_at = DateTime.utc_now(:millisecond)

    event_fields = %{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      modality: :text,
      occurred_at: occurred_at
    }

    started =
      struct!(
        ParticipantTurnStarted,
        Map.merge(event_fields, %{id: Id.generate(:event), sequence: state.next_sequence})
      )

    completed =
      struct!(
        ParticipantTurnCompleted,
        Map.merge(event_fields, %{id: Id.generate(:event), sequence: state.next_sequence + 1})
      )

    state = EventPublisher.publish(state, connection.pid, started)
    archive_recorder = ArchiveRecorder.accepted_input(state.archive_recorder, command, :text)
    state = %{state | archive_recorder: archive_recorder}
    state = EventPublisher.publish(state, connection.pid, completed)
    %{state | next_sequence: state.next_sequence + 2}
  end

  defp agent_busy(reason) do
    Error.new(
      :agent_busy,
      "The room agent cannot accept this turn right now.",
      retryable: true,
      details: %{"reason" => Atom.to_string(reason)}
    )
  end
end
