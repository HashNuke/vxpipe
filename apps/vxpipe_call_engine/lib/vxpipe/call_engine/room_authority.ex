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
  alias Vxpipe.CallEngine.OpeningAudio.{CachedPlaybackRequest, FilePlaybackRequest}
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request, as: TransferRequest

  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan, TextToSpeechRequest}

  alias Vxpipe.CallEngine.Room.Snapshot

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    AgentTransfer,
    CallerIdle,
    ConnectionLifecycle,
    EndCall,
    FirstMessage,
    InputTurns,
    OpeningAudio,
    ParticipantLifecycle,
    State,
    Startup,
    StartupReadiness,
    ToolCalls
  }

  @call_timeout 5_000
  @transfer_timeout 30_000

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

  @spec transfer(TransferRequest.t()) ::
          {:ok, map()} | {:error, :rejected | :unavailable}
  def transfer(%TransferRequest{} = request) do
    GenServer.call(
      via(request.tenant_id, request.room_id),
      {:transfer_agent, request},
      @transfer_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
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

    with {:ok, call_lifecycle} <- StartupReadiness.bind(room_source, incarnation_id) do
      state =
        State.new(
          ArchiveRecorder.new(room_source, incarnation_id, options),
          build_snapshot(room_source, incarnation_id, options),
          initial_speech_to_text_runtime(room_source),
          OpeningAudio.new(room_source, Keyword.get(options, :opening_audio)),
          FirstMessage.new(room_source),
          call_lifecycle
        )

      case Startup.start_agent(room_source, options, state) do
        {:ok, state} ->
          archive_recorder = ArchiveRecorder.room_opened(state.archive_recorder, state.snapshot)
          {:ok, %{state | archive_recorder: archive_recorder}}

        {:error, reason} ->
          {:stop, reason}
      end
    else
      {:error, reason} -> {:stop, reason}
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
        case begin_connection_startup(command, state) do
          {:ok, state} ->
            {:reply, reply, CallerIdle.reconcile(state)}

          {:error, %Error{code: code} = error} ->
            {:stop, code, {:error, error}, state}
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
    case ConnectionLifecycle.bind_speech_to_text(
           command,
           caller,
           subscriber,
           capability,
           ingress,
           state
         ) do
      {:reply, :ok, state} ->
        case StartupReadiness.ready(state) do
          {:ok, state} -> {:reply, :ok, CallerIdle.reconcile(state)}
          {:error, %Error{code: code} = error} -> {:stop, code, {:error, error}, state}
        end

      other ->
        other
    end
  end

  def handle_call({:detach_connection, command, subscriber}, {caller, _tag}, state) do
    case ConnectionLifecycle.detach(command, caller, subscriber, state) do
      {:reply, reply, state} -> {:reply, reply, CallerIdle.reconcile(state)}
    end
  end

  def handle_call({:send_text, command}, {caller, _tag}, state) do
    InputTurns.accept_text(command, caller, state)
  end

  def handle_call({:transfer_agent, %TransferRequest{} = request}, _from, state) do
    AgentTransfer.commit(request, state)
  end

  @impl true
  def handle_info(
        {:vxpipe_capability_continuation_started, capability, %ContinueAgent{} = command},
        state
      ) do
    state = AgentOutput.continuation_started(capability, command, state)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle_info({:vxpipe_capability_text, capability, command, text}, state) do
    {:noreply, AgentOutput.text(capability, command, text, state)}
  end

  def handle_info({:vxpipe_capability_text_complete, capability, command}, state) do
    state = AgentOutput.text_complete(capability, command, state)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle_info({:vxpipe_capability_tool_started, capability, command, call}, state) do
    state = ToolCalls.started(state, capability, command, call)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle_info(
        {:vxpipe_capability_tool_accepted, capability, command, call, _acknowledgement},
        state
      ) do
    state = ToolCalls.accepted_background(state, capability, command, call)
    {:noreply, CallerIdle.reconcile(state)}
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

  def handle_info({:vxpipe_platform_effect, capability, context, :hangup}, state) do
    case EndCall.authorize(capability, context, state) do
      :ok -> {:stop, {:shutdown, :agent_hangup}, state}
      {:error, %Error{}} -> {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_platform_effect, capability, %ToolContext{} = context,
         :participant_transfer_committed},
        state
      ) do
    {:noreply, AgentTransfer.teardown_source(state, capability, context)}
  end

  def handle_info(
        {:vxpipe_call_lifecycle, lifecycle, :readiness},
        %{call_lifecycle: lifecycle, startup_ready?: false} = state
      ) do
    ConnectionLifecycle.notify(state.connections, :call_start_failed)
    {:stop, {:shutdown, :startup_readiness_timeout}, state}
  end

  def handle_info(
        {:vxpipe_call_lifecycle, lifecycle, {:startup_failure, reason}},
        %{call_lifecycle: lifecycle, startup_ready?: false} = state
      ) do
    ConnectionLifecycle.notify(state.connections, :call_start_failed)
    {:stop, {:shutdown, {:startup_failure, reason}}, state}
  end

  def handle_info(
        {:vxpipe_call_lifecycle, lifecycle, {:idle, token}},
        %{call_lifecycle: lifecycle} = state
      ) do
    {:noreply, CallerIdle.notify(token, state)}
  end

  def handle_info(
        {:vxpipe_call_lifecycle, lifecycle, :max_duration},
        %{call_lifecycle: lifecycle} = state
      ) do
    ConnectionLifecycle.notify(state.connections, :maximum_duration_reached)
    {:stop, {:shutdown, :maximum_duration_reached}, state}
  end

  def handle_info({:vxpipe_call_lifecycle, _lifecycle, _event}, state), do: {:noreply, state}

  def handle_info({:vxpipe_capability_failed, capability, command, reason}, state) do
    state = AgentOutput.failed(capability, command, reason, state)
    {:noreply, CallerIdle.reconcile(state)}
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

  def handle_info(
        {:vxpipe_opening_audio_playback, worker, request, status},
        state
      )
      when (is_struct(request, FilePlaybackRequest) or
              is_struct(request, CachedPlaybackRequest)) and
             status in [:started, :completed] do
    handle_asset_opening_audio_playback(worker, request, status, state)
  end

  def handle_info(
        {:vxpipe_opening_audio_playback, worker, request, {:progress, played_ms, total_ms}},
        state
      )
      when (is_struct(request, FilePlaybackRequest) or
              is_struct(request, CachedPlaybackRequest)) and
             is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms do
    handle_asset_opening_audio_playback(
      worker,
      request,
      {:progress, played_ms, total_ms},
      state
    )
  end

  def handle_info(
        {:vxpipe_opening_audio_unavailable, worker, request, _reason},
        state
      )
      when is_struct(request, FilePlaybackRequest) or
             is_struct(request, CachedPlaybackRequest) do
    if OpeningAudio.asset_failure?(state.opening_audio, worker, request) do
      OpeningAudio.failed(state.opening_audio)
      {:stop, :opening_audio_unavailable, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:vxpipe_tts_unavailable, capability, _reason}, state) do
    if OpeningAudio.awaiting_text_playback?(state.opening_audio) do
      OpeningAudio.failed(state.opening_audio)
      {:stop, :opening_audio_unavailable, state}
    else
      state = AgentOutput.unavailable(capability, state)
      {:noreply, CallerIdle.reconcile(state)}
    end
  end

  def handle_info({:vxpipe_stt_signal, capability, identity, %Signal{} = signal}, state) do
    {:noreply, InputTurns.speech_to_text(capability, identity, signal, state)}
  end

  def handle_info({:vxpipe_stt_unavailable, capability, identity, _reason}, state) do
    state = ConnectionLifecycle.speech_to_text_unavailable(capability, identity, state)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{text_to_speech_capability: %{monitor: monitor}} = state
      ) do
    if OpeningAudio.awaiting_text_playback?(state.opening_audio) do
      OpeningAudio.failed(state.opening_audio)
      {:stop, :opening_audio_unavailable, state}
    else
      ConnectionLifecycle.notify(state.connections, :agent_unavailable)
      {:noreply, %{state | text_to_speech_capability: nil}}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    if OpeningAudio.worker_monitor?(state.opening_audio, monitor) do
      OpeningAudio.failed(state.opening_audio)
      {:stop, :opening_audio_unavailable, state}
    else
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

      {:noreply, CallerIdle.reconcile(state)}
    end
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
        continue_after_opening_audio(opening_audio, state)

      :unrelated ->
        state = AgentOutput.playback(capability, request, status, state)

        if status == :completed do
          {:noreply, CallerIdle.reconcile(state)}
        else
          {:noreply, state}
        end
    end
  end

  defp handle_asset_opening_audio_playback(worker, request, status, state) do
    case OpeningAudio.asset_playback(state.opening_audio, worker, request, status) do
      {:handled, opening_audio} -> continue_after_opening_audio(opening_audio, state)
      :unrelated -> {:noreply, state}
    end
  end

  defp continue_after_opening_audio(opening_audio, state) do
    state = %{state | opening_audio: opening_audio}

    state =
      if OpeningAudio.admission(opening_audio) == :open do
        ConnectionLifecycle.open_inputs(state)
      else
        state
      end

    case FirstMessage.start(state) do
      {:ok, state} -> {:noreply, CallerIdle.reconcile(state)}
      {:error, %Error{code: code}} -> {:stop, code, state}
    end
  end

  defp begin_connection_startup(command, state) do
    connection = Map.fetch!(state.connections, command.connection_id)

    with {:ok, opening_audio} <-
           OpeningAudio.start(
             state.opening_audio,
             command,
             connection,
             state.text_to_speech_capability,
             state.snapshot,
             self()
           ),
         {:ok, state} <-
           StartupReadiness.connection_attached(
             command,
             %{state | opening_audio: opening_audio}
           ) do
      {:ok, state}
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
