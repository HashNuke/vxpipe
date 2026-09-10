defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    ContinueAgent,
    CreateRoom,
    JoinParticipant,
    SendText
  }

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  alias Vxpipe.CallEngine.{ResolvedCallPlan, TextToSpeechRequest}

  alias Vxpipe.CallEngine.Room.Snapshot

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    ConnectionLifecycle,
    InputTurns,
    OpeningAudio,
    ParticipantLifecycle,
    State,
    Startup,
    ToolCalls
  }

  @call_timeout 5_000

  def start_link(options) do
    {tenant_id, room_id} = room_identity(options)
    name = via(tenant_id, room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @call_timeout)
  end

  def input_admission(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :input_admission, @call_timeout)
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
    room_source = room_source(options)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    state =
      State.new(
        ArchiveRecorder.new(room_source, incarnation_id, options),
        build_snapshot(room_source, incarnation_id, options),
        initial_speech_to_text_runtime(room_source),
        OpeningAudio.new(room_source)
      )

    case Startup.start_agent(room_source, options, state) do
      {:ok, state} ->
        archive_recorder = ArchiveRecorder.room_opened(state.archive_recorder, state.snapshot)
        {:ok, %{state | archive_recorder: archive_recorder}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call(:input_admission, _from, state) do
    {:reply, OpeningAudio.admission(state.opening_audio), state}
  end

  def handle_call({:join_participant, command}, _from, state) do
    ParticipantLifecycle.join(command, state)
  end

  def handle_call(
        {:attach_connection, command, subscriber, output_sink},
        {caller, _tag},
        state
      ) do
    case ConnectionLifecycle.attach(command, caller, subscriber, output_sink, state) do
      {:reply, {:ok, _role, _runtime} = reply, state} ->
        connection = Map.fetch!(state.connections, command.connection_id)

        case OpeningAudio.start(
               state.opening_audio,
               command,
               connection,
               state.text_to_speech_capability,
               state.snapshot
             ) do
          {:ok, opening_audio} ->
            {:reply, reply, %{state | opening_audio: opening_audio}}

          {:error, error} ->
            {:stop, :opening_audio_unavailable, {:error, error}, state}
        end

      other ->
        other
    end
  end

  def handle_call(
        {:bind_speech_to_text, command, subscriber, capability, ingress},
        {caller, _tag},
        state
      ) do
    ConnectionLifecycle.bind_speech_to_text(
      command,
      caller,
      subscriber,
      capability,
      ingress,
      state
    )
  end

  def handle_call({:detach_connection, command, subscriber}, {caller, _tag}, state) do
    ConnectionLifecycle.detach(command, caller, subscriber, state)
  end

  def handle_call({:send_text, command}, {caller, _tag}, state) do
    InputTurns.accept_text(command, caller, state)
  end

  @impl true
  def handle_info(
        {:vxpipe_capability_continuation_started, capability, %ContinueAgent{} = command},
        state
      ) do
    {:noreply, AgentOutput.continuation_started(capability, command, state)}
  end

  def handle_info({:vxpipe_capability_text, capability, command, text}, state) do
    {:noreply, AgentOutput.text(capability, command, text, state)}
  end

  def handle_info({:vxpipe_capability_text_complete, capability, command}, state) do
    {:noreply, AgentOutput.text_complete(capability, command, state)}
  end

  def handle_info({:vxpipe_capability_tool_started, capability, command, call}, state) do
    {:noreply, ToolCalls.started(state, capability, command, call)}
  end

  def handle_info(
        {:vxpipe_capability_tool_accepted, capability, command, call, _acknowledgement},
        state
      ) do
    {:noreply, ToolCalls.accepted_background(state, capability, command, call)}
  end

  def handle_info(
        {:vxpipe_capability_tool_completed, capability, command, call, result},
        state
      ) do
    {:noreply, ToolCalls.completed(state, capability, command, call, result)}
  end

  def handle_info({:vxpipe_capability_tool_failed, capability, command, call, reason}, state) do
    {:noreply, ToolCalls.failed(state, capability, command, call, reason)}
  end

  def handle_info({:vxpipe_capability_failed, capability, command, reason}, state) do
    {:noreply, AgentOutput.failed(capability, command, reason, state)}
  end

  def handle_info(
        {:vxpipe_tts_playback, capability, %TextToSpeechRequest{} = request, status},
        state
      )
      when status in [:started, :completed] do
    handle_text_to_speech_playback(capability, request, status, state)
  end

  def handle_info(
        {:vxpipe_tts_playback, capability, %TextToSpeechRequest{} = request,
         {:progress, played_ms, total_ms}},
        state
      )
      when is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms do
    handle_text_to_speech_playback(
      capability,
      request,
      {:progress, played_ms, total_ms},
      state
    )
  end

  def handle_info({:vxpipe_tts_unavailable, capability, _reason}, state) do
    if OpeningAudio.awaiting_playback?(state.opening_audio) do
      {:stop, :opening_audio_unavailable, state}
    else
      {:noreply, AgentOutput.unavailable(capability, state)}
    end
  end

  def handle_info({:vxpipe_stt_signal, capability, identity, %Signal{} = signal}, state) do
    {:noreply, InputTurns.speech_to_text(capability, identity, signal, state)}
  end

  def handle_info({:vxpipe_stt_unavailable, capability, identity, _reason}, state) do
    state = ConnectionLifecycle.speech_to_text_unavailable(capability, identity, state)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{text_to_speech_capability: %{monitor: monitor}} = state
      ) do
    if OpeningAudio.awaiting_playback?(state.opening_audio) do
      {:stop, :opening_audio_unavailable, state}
    else
      ConnectionLifecycle.notify(state.connections, :agent_unavailable)
      {:noreply, %{state | text_to_speech_capability: nil}}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    state =
      cond do
        Map.has_key?(state.participant_monitors, monitor) ->
          ParticipantLifecycle.remove(monitor, reason, state)

        Map.has_key?(state.connection_monitors, monitor) ->
          ConnectionLifecycle.remove(monitor, reason, state)

        Map.has_key?(state.speech_to_text_monitors, monitor) ->
          ConnectionLifecycle.remove_unavailable_speech_to_text(monitor, state)

        state.text_capability != nil and state.text_capability.monitor != nil and
            state.text_capability.monitor == monitor ->
          ConnectionLifecycle.notify(state.connections, :agent_unavailable)
          %{state | text_capability: nil}

        true ->
          state
      end

    {:noreply, state}
  end

  defp room_source(options) do
    case Keyword.fetch(options, :plan) do
      {:ok, %ResolvedCallPlan{} = plan} -> plan
      :error -> Keyword.fetch!(options, :command)
    end
  end

  defp initial_speech_to_text_runtime(%CreateRoom{}), do: :application
  defp initial_speech_to_text_runtime(%ResolvedCallPlan{}), do: %{}

  defp handle_text_to_speech_playback(capability, request, status, state) do
    opening_result =
      if state.text_to_speech_capability != nil and
           state.text_to_speech_capability.pid == capability do
        OpeningAudio.playback(state.opening_audio, request, status)
      else
        :unrelated
      end

    case opening_result do
      {:handled, opening_audio} ->
        state = %{state | opening_audio: opening_audio}

        state =
          if OpeningAudio.admission(opening_audio) == :open do
            ConnectionLifecycle.open_inputs(state)
          else
            state
          end

        {:noreply, state}

      :unrelated ->
        {:noreply, AgentOutput.playback(capability, request, status, state)}
    end
  end

  defp room_identity(options) do
    source = room_source(options)
    {source.tenant_id, source.room_id}
  end

  defp build_snapshot(%CreateRoom{} = command, incarnation_id, _options) do
    %Snapshot{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: command.actor_id,
      created_by_command_id: command.id
    }
  end

  defp build_snapshot(%ResolvedCallPlan{} = plan, incarnation_id, options) do
    %Snapshot{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: plan.actor_id,
      created_by_command_id: Keyword.fetch!(options, :start_command_id)
    }
  end

  defp via(tenant_id, room_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}}}
  end
end
