defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Capability.{DeterministicText, ModelInference, TextToSpeech}
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  alias Vxpipe.CallEngine.{
    Error,
    Id,
    RoomCapabilitySupervisor,
    RoomParticipantSupervisor,
    TextToSpeechRequest,
    TurnInterrupter
  }

  alias Vxpipe.CallEngine.Room.Snapshot

  @call_timeout 5_000

  def start_link(options) do
    command = Keyword.fetch!(options, :command)
    name = via(command.tenant_id, command.room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @call_timeout)
  end

  def join_participant(room_authority, %JoinParticipant{} = command) do
    GenServer.call(room_authority, {:join_participant, command}, @call_timeout)
  end

  def attach_connection(
        room_authority,
        %AttachConnection{} = command,
        subscriber,
        output_sink
      )
      when is_pid(subscriber) do
    GenServer.call(
      room_authority,
      {:attach_connection, command, subscriber, output_sink},
      @call_timeout
    )
  end

  def send_text(room_authority, %SendText{} = command) do
    GenServer.call(room_authority, {:send_text, command}, @call_timeout)
  end

  def bind_speech_to_text(
        room_authority,
        %AttachConnection{} = command,
        subscriber,
        capability,
        ingress
      )
      when is_pid(subscriber) and is_pid(capability) and is_pid(ingress) do
    GenServer.call(
      room_authority,
      {:bind_speech_to_text, command, subscriber, capability, ingress},
      @call_timeout
    )
  end

  def detach_connection(room_authority, %AttachConnection{} = command, subscriber)
      when is_pid(subscriber) do
    GenServer.call(room_authority, {:detach_connection, command, subscriber}, @call_timeout)
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    state = %{
      connection_monitors: %{},
      connections: %{},
      agent_turns: %{},
      next_sequence: 1,
      participant_monitors: %{},
      participant_ids: MapSet.new(),
      participant_roles: %{},
      snapshot: build_snapshot(command, incarnation_id),
      speech_to_text_monitors: %{},
      text_capability: nil,
      text_to_speech_capability: nil
    }

    case start_configured_agent(command, state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:join_participant, command}, _from, state) do
    if MapSet.member?(state.participant_ids, command.participant_id) do
      {:reply, {:error, participant_already_exists(command.participant_id)}, state}
    else
      admit_participant(command, state)
    end
  end

  def handle_call(
        {:attach_connection, command, subscriber, output_sink},
        {caller, _tag},
        state
      ) do
    case authorize_attachment(command, caller, subscriber, state) do
      :ok -> put_connection(command, subscriber, output_sink, state)
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:bind_speech_to_text, command, subscriber, capability, ingress},
        {caller, _tag},
        state
      ) do
    case authorize_speech_to_text_binding(command, caller, subscriber, state) do
      :ok -> bind_connection_speech_to_text(command, capability, ingress, state)
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:detach_connection, command, subscriber}, {caller, _tag}, state) do
    case authorize_detachment(command, caller, subscriber, state) do
      :ok -> {:reply, :ok, remove_connection_by_id(command.connection_id, state)}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:send_text, command}, {caller, _tag}, state) do
    case authorize_text(command, caller, state) do
      {:ok, capability} ->
        case interrupt_active_turns(command, state) do
          {:ok, state} ->
            case respond(capability, command) do
              :ok ->
                state = state |> put_agent_turn(command) |> emit_participant_text_turn(command)
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

  @impl true
  def handle_info({:vxpipe_capability_text, capability, command, text}, state) do
    state = emit_text_turn(capability, command, text, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_capability_text_complete, capability, command}, state) do
    state = complete_text_generation(capability, command, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_capability_tool_started, capability, command, call}, state) do
    {:noreply, emit_tool_call_started(capability, command, call, state)}
  end

  def handle_info(
        {:vxpipe_capability_tool_completed, capability, command, call, result},
        state
      ) do
    {:noreply, emit_tool_call_completed(capability, command, call, result, state)}
  end

  def handle_info({:vxpipe_capability_tool_failed, capability, command, call, reason}, state) do
    {:noreply, emit_tool_call_failed(capability, command, call, reason, state)}
  end

  def handle_info({:vxpipe_capability_failed, capability, command, reason}, state) do
    state = emit_agent_turn_failed(capability, command, reason, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_tts_playback, capability, %TextToSpeechRequest{} = request, status},
        state
      )
      when status in [:started, :completed] do
    state = handle_text_to_speech_playback(capability, request, status, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_tts_playback, capability, %TextToSpeechRequest{} = request,
         {:progress, played_ms, total_ms}},
        state
      )
      when is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms do
    state =
      handle_text_to_speech_playback(
        capability,
        request,
        {:progress, played_ms, total_ms},
        state
      )

    {:noreply, state}
  end

  def handle_info({:vxpipe_tts_unavailable, capability, _reason}, state) do
    state = handle_text_to_speech_unavailable(capability, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_stt_signal, capability, identity, %Signal{} = signal}, state) do
    state = handle_speech_to_text_signal(capability, identity, signal, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_stt_unavailable, capability, identity, _reason}, state) do
    state = handle_speech_to_text_unavailable(capability, identity, state)
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      cond do
        Map.has_key?(state.participant_monitors, monitor) ->
          remove_participant(monitor, state)

        Map.has_key?(state.connection_monitors, monitor) ->
          remove_connection(monitor, state)

        Map.has_key?(state.speech_to_text_monitors, monitor) ->
          remove_unavailable_speech_to_text(monitor, state)

        state.text_capability != nil and state.text_capability.monitor == monitor ->
          notify_connections(state.connections, :agent_unavailable)
          %{state | text_capability: nil}

        state.text_to_speech_capability != nil and
            state.text_to_speech_capability.monitor == monitor ->
          notify_connections(state.connections, :agent_unavailable)
          %{state | text_to_speech_capability: nil}

        true ->
          state
      end

    {:noreply, state}
  end

  defp start_configured_agent(%CreateRoom{agent: nil}, state), do: {:ok, state}

  defp start_configured_agent(%CreateRoom{} = command, state) do
    with {:ok, join_command} <-
           JoinParticipant.new(
             tenant_id: command.tenant_id,
             actor_id: command.actor_id,
             room_id: command.room_id,
             participant_id: command.agent_participant_id,
             role: :agent,
             deadline: command.deadline
           ),
         {:ok, participant, state} <- start_participant(join_command, state),
         {:ok, module, capability} <-
           start_text_capability(command.agent, participant.participant_id, state) do
      text_capability = %{
        module: module,
        monitor: Process.monitor(capability),
        participant_id: participant.participant_id,
        pid: capability
      }

      state = %{state | text_capability: text_capability}
      start_configured_text_to_speech(participant.participant_id, state)
    else
      _error -> {:error, :agent_start_failed}
    end
  end

  defp start_text_capability(:deterministic_text, participant_id, state) do
    case RoomCapabilitySupervisor.start_deterministic_text(
           state.snapshot.incarnation_id,
           self(),
           participant_id
         ) do
      {:ok, capability} -> {:ok, DeterministicText, capability}
      {:error, _reason} = error -> error
    end
  end

  defp start_text_capability(:model_inference, participant_id, state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    options = Keyword.fetch!(settings, :model_inference)

    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability} <-
             RoomCapabilitySupervisor.start_model_inference(
               state.snapshot.incarnation_id,
               self(),
               participant_id,
               {provider_module, provider_config},
               options
             ) do
        {:ok, ModelInference, capability}
      end
    else
      {:error, :model_inference_disabled}
    end
  end

  defp start_configured_text_to_speech(participant_id, state) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    options = Keyword.fetch!(settings, :text_to_speech)

    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability} <-
             RoomCapabilitySupervisor.start_text_to_speech(
               state.snapshot.incarnation_id,
               self(),
               participant_id,
               {provider_module, provider_config},
               Keyword.fetch!(options, :transport),
               Keyword.fetch!(options, :maximum_requests)
             ) do
        text_to_speech_capability = %{
          monitor: Process.monitor(capability),
          participant_id: participant_id,
          pid: capability
        }

        {:ok, %{state | text_to_speech_capability: text_to_speech_capability}}
      else
        _error -> {:error, :text_to_speech_start_failed}
      end
    else
      {:ok, state}
    end
  end

  defp authorize_attachment(command, caller, subscriber, state) do
    cond do
      caller != subscriber ->
        {:error, connection_not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      not MapSet.member?(state.participant_ids, command.participant_id) ->
        {:error, participant_not_found(command.participant_id)}

      not agent_ready?(state) ->
        {:error, agent_not_ready()}

      Map.has_key?(state.connections, command.connection_id) ->
        {:error, connection_already_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp put_connection(command, subscriber, output_sink, state) do
    monitor = Process.monitor(subscriber)
    role = Map.fetch!(state.participant_roles, command.participant_id)

    connection = %{
      actor_id: command.actor_id,
      participant_id: command.participant_id,
      pid: subscriber,
      output_sink: output_sink,
      role: role,
      speech_to_text: nil
    }

    state = %{
      state
      | connection_monitors: Map.put(state.connection_monitors, monitor, command.connection_id),
        connections: Map.put(state.connections, command.connection_id, connection)
    }

    {:reply, {:ok, role}, state}
  end

  defp authorize_speech_to_text_binding(command, caller, subscriber, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      caller != subscriber ->
        {:error, connection_not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != subscriber or
          connection.participant_id != command.participant_id ->
        {:error, connection_not_attached(command.connection_id)}

      connection.role != :human or connection.speech_to_text != nil ->
        {:error, speech_to_text_not_bindable(command.connection_id)}

      true ->
        :ok
    end
  end

  defp authorize_detachment(command, caller, subscriber, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      caller != subscriber ->
        {:error, connection_not_attached(command.connection_id)}

      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != subscriber or
          connection.participant_id != command.participant_id ->
        {:error, connection_not_attached(command.connection_id)}

      true ->
        :ok
    end
  end

  defp bind_connection_speech_to_text(command, capability, ingress, state) do
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    connection = Map.fetch!(state.connections, command.connection_id)

    speech_to_text = %{
      capability: capability,
      capability_monitor: capability_monitor,
      ingress: ingress,
      ingress_monitor: ingress_monitor,
      turn: nil
    }

    connection = %{connection | speech_to_text: speech_to_text}

    speech_to_text_monitors =
      state.speech_to_text_monitors
      |> Map.put(capability_monitor, command.connection_id)
      |> Map.put(ingress_monitor, command.connection_id)

    state = %{
      state
      | connections: Map.put(state.connections, command.connection_id, connection),
        speech_to_text_monitors: speech_to_text_monitors
    }

    {:reply, :ok, state}
  end

  defp authorize_text(command, caller, state) do
    connection = Map.get(state.connections, command.connection_id)

    cond do
      command.incarnation_id != state.snapshot.incarnation_id ->
        {:error, room_incarnation_changed(state.snapshot.incarnation_id)}

      connection == nil or connection.pid != caller or
          connection.participant_id != command.participant_id ->
        {:error, connection_not_attached(command.connection_id)}

      not agent_ready?(state) ->
        {:error, agent_not_ready()}

      true ->
        {:ok, state.text_capability}
    end
  end

  defp agent_ready?(%{text_capability: nil}), do: false

  defp agent_ready?(state) do
    MapSet.member?(state.participant_ids, state.text_capability.participant_id)
  end

  defp handle_speech_to_text_signal(capability, identity, signal, state) do
    case authorized_speech_to_text(capability, identity, state) do
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

      case interrupt_active_turns(audio_turn_interrupter(turn, connection_id, connection), state) do
        {:ok, state} ->
          occurred_at = DateTime.utc_now(:millisecond)

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
            occurred_at: occurred_at
          }

          send(connection.pid, {:vxpipe_event, started})

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

    send(connection.pid, {:vxpipe_event, event})
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

    send(connection.pid, {:vxpipe_event, event})
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
        case interrupt_active_turns(command, state) do
          {:ok, state} ->
            case respond(state.text_capability, command) do
              :ok ->
                put_agent_turn(state, command)

              {:error, reason} ->
                state = put_agent_turn(state, command)

                send(
                  self(),
                  {:vxpipe_capability_failed, state.text_capability.pid, command,
                   failure_reason(reason)}
                )

                state
            end

          {:error, reason} ->
            state = put_agent_turn(state, command)

            send(
              self(),
              {:vxpipe_capability_failed, state.text_capability.pid, command,
               failure_reason(reason)}
            )

            state
        end

      _empty_or_invalid ->
        state
    end
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

  defp authorized_speech_to_text(capability, identity, state) do
    connection_id = Map.get(identity, :connection_id)
    connection = Map.get(state.connections, connection_id)

    if connection != nil and connection.speech_to_text != nil and
         connection.speech_to_text.capability == capability and
         connection.participant_id == Map.get(identity, :participant_id) and
         state.snapshot.tenant_id == Map.get(identity, :tenant_id) and
         state.snapshot.room_id == Map.get(identity, :room_id) and
         state.snapshot.incarnation_id == Map.get(identity, :incarnation_id) do
      {:ok, connection_id, connection}
    else
      :error
    end
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

    send(connection.pid, {:vxpipe_event, started})
    send(connection.pid, {:vxpipe_event, completed})
    %{state | next_sequence: state.next_sequence + 2}
  end

  defp emit_text_turn(capability, command, text, state) do
    connection = Map.get(state.connections, command.connection_id)

    if active_agent_turn?(command, state) and state.text_capability != nil and
         state.text_capability.pid == capability and
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

      send(connection.pid, {:vxpipe_event, output})

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
          text: text,
          output_sink: connection.output_sink
        }

        case TextToSpeech.synthesize(state.text_to_speech_capability.pid, request) do
          :ok ->
            update_agent_turn(state, command, fn turn ->
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

  defp emit_agent_turn_failed(capability, command, reason, state) do
    connection = Map.get(state.connections, command.connection_id)

    if active_agent_turn?(command, state) and state.text_capability != nil and
         state.text_capability.pid == capability and
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

      send(connection.pid, {:vxpipe_event, event})

      state
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> delete_agent_turn(command)
    else
      state
    end
  end

  defp emit_tool_call_started(capability, command, call, state) do
    if authorized_tool_event?(capability, command, state) do
      connection = Map.fetch!(state.connections, command.connection_id)

      event =
        struct!(
          ToolCallStarted,
          Map.merge(tool_event_fields(command, call, state), %{arguments: call.arguments})
        )

      send(connection.pid, {:vxpipe_event, event})

      state
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> update_agent_turn(command, fn turn ->
        %{turn | active_tool_calls: Map.put(turn.active_tool_calls, call.id, call)}
      end)
    else
      state
    end
  end

  defp emit_tool_call_completed(capability, command, call, result, state) do
    emit_tool_call_stopped(capability, command, call, state, fn fields ->
      struct!(ToolCallCompleted, Map.put(fields, :result, result))
    end)
  end

  defp emit_tool_call_failed(capability, command, call, reason, state) do
    emit_tool_call_stopped(capability, command, call, state, fn fields ->
      struct!(ToolCallFailed, Map.put(fields, :reason, reason))
    end)
  end

  defp emit_tool_call_stopped(capability, command, call, state, build_event) do
    turn = Map.get(state.agent_turns, turn_key(command))

    if authorized_tool_event?(capability, command, state) and turn != nil and
         Map.has_key?(turn.active_tool_calls, call.id) do
      connection = Map.fetch!(state.connections, command.connection_id)
      send(connection.pid, {:vxpipe_event, build_event.(tool_event_fields(command, call, state))})

      state
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> update_agent_turn(command, fn turn ->
        %{turn | active_tool_calls: Map.delete(turn.active_tool_calls, call.id)}
      end)
    else
      state
    end
  end

  defp authorized_tool_event?(capability, command, state) do
    connection = Map.get(state.connections, command.connection_id)

    active_agent_turn?(command, state) and state.text_capability != nil and
      state.text_capability.pid == capability and connection != nil and
      connection.participant_id == command.participant_id
  end

  defp tool_event_fields(command, call, state) do
    %{
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
      tool_call_id: call.id,
      name: call.name,
      occurred_at: DateTime.utc_now(:millisecond)
    }
  end

  defp handle_text_to_speech_playback(capability, request, status, state) do
    connection = Map.get(state.connections, request.connection_id)

    if authorized_text_to_speech?(capability, request, connection, state) do
      case status do
        :started ->
          emit_agent_speech_started(request, connection, state)

        {:progress, played_ms, total_ms} ->
          emit_agent_speech_progressed(request, connection, played_ms, total_ms, state)

        :completed ->
          complete_spoken_segment(request, connection, state)
      end
    else
      state
    end
  end

  defp authorized_text_to_speech?(capability, request, connection, state) do
    active_agent_turn?(request, state) and state.text_to_speech_capability != nil and
      state.text_to_speech_capability.pid == capability and connection != nil and
      connection.output_sink == request.output_sink and
      connection.participant_id == request.source_participant_id and
      state.snapshot.tenant_id == request.tenant_id and state.snapshot.room_id == request.room_id and
      state.snapshot.incarnation_id == request.incarnation_id
  end

  defp emit_agent_speech_started(request, connection, state) do
    event = struct!(AgentSpeechStarted, agent_event_fields(request, state))

    send(connection.pid, {:vxpipe_event, event})
    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_agent_speech_progressed(request, connection, played_ms, total_ms, state) do
    event =
      struct!(
        AgentSpeechProgressed,
        Map.merge(agent_event_fields(request, state), %{played_ms: played_ms, total_ms: total_ms})
      )

    send(connection.pid, {:vxpipe_event, event})
    %{state | next_sequence: state.next_sequence + 1}
  end

  defp emit_agent_turn_completed(%TextToSpeechRequest{} = request, connection, state) do
    event = struct!(AgentTurnCompleted, agent_event_fields(request, state))

    send(connection.pid, {:vxpipe_event, event})

    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> delete_agent_turn(request)
  end

  defp emit_agent_turn_completed(command, connection, occurred_at, state) do
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

    send(connection.pid, {:vxpipe_event, event})

    state
    |> Map.update!(:next_sequence, &(&1 + 1))
    |> delete_agent_turn(command)
  end

  defp complete_text_generation(capability, command, state) do
    connection = Map.get(state.connections, command.connection_id)

    if active_agent_turn?(command, state) and state.text_capability != nil and
         state.text_capability.pid == capability and connection != nil and
         connection.participant_id == command.participant_id do
      turn = Map.fetch!(state.agent_turns, turn_key(command))

      if turn.pending_speech == 0 do
        emit_agent_turn_completed(command, connection, DateTime.utc_now(:millisecond), state)
      else
        update_agent_turn(state, command, &%{&1 | generation_complete?: true})
      end
    else
      state
    end
  end

  defp complete_spoken_segment(request, connection, state) do
    turn = Map.fetch!(state.agent_turns, turn_key(request))
    turn = %{turn | pending_speech: max(turn.pending_speech - 1, 0)}
    state = put_agent_turn_state(state, request, turn)

    if turn.generation_complete? and turn.pending_speech == 0 do
      emit_agent_turn_completed(request, connection, state)
    else
      state
    end
  end

  defp interrupt_active_turns(%SendText{run_immediately: false}, state), do: {:ok, state}

  defp interrupt_active_turns(%SendText{} = command, state) do
    interrupter = %TurnInterrupter{
      participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id
    }

    interrupt_active_turns(interrupter, state)
  end

  defp interrupt_active_turns(%TurnInterrupter{}, %{agent_turns: agent_turns} = state)
       when map_size(agent_turns) == 0,
       do: {:ok, state}

  defp interrupt_active_turns(%TurnInterrupter{} = interrupter, state) do
    turns = state.agent_turns |> Map.values() |> Enum.sort_by(& &1.order, :desc)
    turn_ids = Enum.map(turns, &turn_key(&1.command))

    with {:ok, speech_requests} <- interrupt_text_to_speech(state),
         {:ok, _commands} <- interrupt_text_generation(state, turn_ids) do
      played_by_turn =
        Map.new(speech_requests, fn {request, played_ms} ->
          {turn_key(request), played_ms}
        end)

      state = %{state | agent_turns: %{}}

      state =
        Enum.reduce(turns, state, fn turn, state ->
          state = emit_tool_call_cancellations(turn, state)

          emit_agent_turn_interrupted(
            turn.command,
            interrupter,
            Map.get(played_by_turn, turn_key(turn.command), 0),
            state
          )
        end)

      {:ok, state}
    end
  end

  defp interrupt_text_to_speech(%{text_to_speech_capability: nil}), do: {:ok, []}

  defp interrupt_text_to_speech(state) do
    TextToSpeech.interrupt(state.text_to_speech_capability.pid)
  end

  defp interrupt_text_generation(%{text_capability: %{module: ModelInference}} = state, ids) do
    ModelInference.interrupt(state.text_capability.pid, ids)
  end

  defp interrupt_text_generation(_state, _ids), do: {:ok, []}

  defp emit_agent_turn_interrupted(command, interrupter, played_ms, state) do
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

      send(connection.pid, {:vxpipe_event, event})
      %{state | next_sequence: state.next_sequence + 1}
    else
      state
    end
  end

  defp emit_tool_call_cancellations(turn, state) do
    connection = Map.get(state.connections, turn.command.connection_id)

    if connection != nil and connection.participant_id == turn.command.participant_id do
      turn.active_tool_calls
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce(state, fn call, state ->
        event = struct!(ToolCallCancelled, tool_event_fields(turn.command, call, state))
        send(connection.pid, {:vxpipe_event, event})
        %{state | next_sequence: state.next_sequence + 1}
      end)
    else
      state
    end
  end

  defp put_agent_turn(state, command) do
    turn = %{
      active_tool_calls: %{},
      command: command,
      generation_complete?: false,
      order: state.next_sequence,
      pending_speech: 0
    }

    %{state | agent_turns: Map.put(state.agent_turns, turn_key(command), turn)}
  end

  defp update_agent_turn(state, command, update) do
    case Map.fetch(state.agent_turns, turn_key(command)) do
      {:ok, turn} -> put_agent_turn_state(state, command, update.(turn))
      :error -> state
    end
  end

  defp put_agent_turn_state(state, command, turn) do
    %{state | agent_turns: Map.put(state.agent_turns, turn_key(command), turn)}
  end

  defp delete_agent_turn(state, command) do
    %{state | agent_turns: Map.delete(state.agent_turns, turn_key(command))}
  end

  defp active_agent_turn?(command, state) do
    case Map.get(state.agent_turns, turn_key(command)) do
      %{command: active} -> active.id == command_id(command)
      nil -> false
    end
  end

  defp turn_key(command) do
    {command.connection_id, command.correlation_id, command_id(command)}
  end

  defp command_id(%SendText{} = command), do: command.id
  defp command_id(%TextToSpeechRequest{} = request), do: request.command_id

  defp agent_event_fields(request, state) do
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

  defp handle_text_to_speech_unavailable(capability, state) do
    if state.text_to_speech_capability != nil and
         state.text_to_speech_capability.pid == capability do
      Process.demonitor(state.text_to_speech_capability.monitor, [:flush])
      notify_connections(state.connections, :agent_unavailable)
      %{state | text_to_speech_capability: nil}
    else
      state
    end
  end

  defp admit_participant(command, state) do
    case start_participant(command, state) do
      {:ok, participant, state} ->
        {:reply, {:ok, participant}, state}

      {:error, :participant_already_exists} ->
        {:reply, {:error, participant_already_exists(command.participant_id)}, state}

      {:error, _reason} ->
        {:reply,
         {:error,
          Error.new(
            :room_start_failed,
            "The participant could not be admitted.",
            retryable: true
          )}, state}
    end
  end

  defp start_participant(command, state) do
    case RoomParticipantSupervisor.start_participant(state.snapshot.incarnation_id, command) do
      {:ok, participant_authority, participant} ->
        monitor = Process.monitor(participant_authority)

        state = %{
          state
          | participant_monitors:
              Map.put(state.participant_monitors, monitor, command.participant_id),
            participant_ids: MapSet.put(state.participant_ids, command.participant_id),
            participant_roles:
              Map.put(state.participant_roles, command.participant_id, participant.role)
        }

        {:ok, participant, state}

      error ->
        error
    end
  end

  defp remove_participant(monitor, state) do
    {participant_id, participant_monitors} = Map.pop(state.participant_monitors, monitor)

    affected_connections =
      Map.filter(state.connections, fn {_connection_id, connection} ->
        connection.participant_id == participant_id
      end)

    notify_connections(affected_connections, :participant_unavailable)

    if state.text_capability != nil and
         state.text_capability.participant_id == participant_id do
      notify_connections(state.connections, :agent_unavailable)

      _ =
        RoomCapabilitySupervisor.stop_capability(
          state.snapshot.incarnation_id,
          state.text_capability.pid
        )
    end

    if state.text_to_speech_capability != nil and
         state.text_to_speech_capability.participant_id == participant_id do
      _ =
        RoomCapabilitySupervisor.stop_capability(
          state.snapshot.incarnation_id,
          state.text_to_speech_capability.pid
        )
    end

    %{
      state
      | participant_monitors: participant_monitors,
        participant_ids: MapSet.delete(state.participant_ids, participant_id),
        participant_roles: Map.delete(state.participant_roles, participant_id)
    }
  end

  defp remove_connection(monitor, state) do
    {connection_id, connection_monitors} = Map.pop(state.connection_monitors, monitor)

    state = %{state | connection_monitors: connection_monitors}
    remove_connection_by_id(connection_id, state)
  end

  defp remove_connection_by_id(nil, state), do: state

  defp remove_connection_by_id(connection_id, state) do
    state = clear_connection_speech_to_text(connection_id, false, state)
    {monitor, connection_monitors} = pop_connection_monitor(connection_id, state)

    if monitor != nil do
      Process.demonitor(monitor, [:flush])
    end

    %{
      state
      | connection_monitors: connection_monitors,
        connections: Map.delete(state.connections, connection_id)
    }
  end

  defp handle_speech_to_text_unavailable(capability, identity, state) do
    case authorized_speech_to_text(capability, identity, state) do
      {:ok, connection_id, _connection} ->
        clear_connection_speech_to_text(connection_id, true, state)

      :error ->
        state
    end
  end

  defp remove_unavailable_speech_to_text(monitor, state) do
    case Map.fetch(state.speech_to_text_monitors, monitor) do
      {:ok, connection_id} -> clear_connection_speech_to_text(connection_id, true, state)
      :error -> state
    end
  end

  defp clear_connection_speech_to_text(connection_id, notify?, state) do
    connection = Map.get(state.connections, connection_id)

    if connection != nil and connection.speech_to_text != nil do
      speech_to_text = connection.speech_to_text
      Process.demonitor(speech_to_text.capability_monitor, [:flush])
      Process.demonitor(speech_to_text.ingress_monitor, [:flush])

      :ok =
        RoomCapabilitySupervisor.stop_speech_to_text(
          state.snapshot.incarnation_id,
          speech_to_text.capability,
          speech_to_text.ingress
        )

      connection = %{connection | speech_to_text: nil}

      speech_to_text_monitors =
        state.speech_to_text_monitors
        |> Map.delete(speech_to_text.capability_monitor)
        |> Map.delete(speech_to_text.ingress_monitor)

      if notify? do
        send(connection.pid, {:vxpipe_connection_unavailable, :speech_to_text_unavailable})
      end

      %{
        state
        | connections: Map.put(state.connections, connection_id, connection),
          speech_to_text_monitors: speech_to_text_monitors
      }
    else
      state
    end
  end

  defp pop_connection_monitor(connection_id, state) do
    case Enum.find(state.connection_monitors, fn {_monitor, id} -> id == connection_id end) do
      {monitor, _connection_id} ->
        {monitor, Map.delete(state.connection_monitors, monitor)}

      nil ->
        {nil, state.connection_monitors}
    end
  end

  defp notify_connections(connections, reason) do
    Enum.each(connections, fn {_connection_id, connection} ->
      send(connection.pid, {:vxpipe_connection_unavailable, reason})
    end)
  end

  defp participant_already_exists(participant_id) do
    Error.new(
      :participant_already_exists,
      "The participant already exists.",
      details: %{"participant_id" => participant_id}
    )
  end

  defp participant_not_found(participant_id) do
    Error.new(
      :participant_not_found,
      "The participant does not exist.",
      details: %{"participant_id" => participant_id}
    )
  end

  defp connection_already_attached(connection_id) do
    Error.new(
      :connection_already_attached,
      "The connection is already attached.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp connection_not_attached(connection_id) do
    Error.new(
      :connection_not_attached,
      "The connection is not attached to this participant.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp speech_to_text_not_bindable(connection_id) do
    Error.new(
      :speech_to_text_not_bindable,
      "Speech-to-text cannot be bound to this connection.",
      details: %{"connection_id" => connection_id}
    )
  end

  defp room_incarnation_changed(incarnation_id) do
    Error.new(
      :room_incarnation_changed,
      "The room incarnation has changed.",
      details: %{"incarnation_id" => incarnation_id}
    )
  end

  defp agent_not_ready do
    Error.new(:agent_not_ready, "The room agent is not ready.", retryable: true)
  end

  defp agent_busy(reason) do
    Error.new(
      :agent_busy,
      "The room agent cannot accept this turn right now.",
      retryable: true,
      details: %{"reason" => Atom.to_string(reason)}
    )
  end

  defp respond(%{module: module, pid: capability}, command) do
    module.respond(capability, command)
  end

  defp failure_reason(reason)
       when reason in [:invalid_response, :provider_timeout, :provider_unavailable],
       do: reason

  defp failure_reason(_reason), do: :provider_unavailable

  defp build_snapshot(%CreateRoom{} = command, incarnation_id) do
    %Snapshot{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: command.actor_id,
      created_by_command_id: command.id
    }
  end

  defp via(tenant_id, room_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}}}
  end
end
