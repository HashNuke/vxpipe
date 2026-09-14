defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    ContinueAgent,
    CreateRoom,
    JoinParticipant,
    ParticipantTransferControl,
    SendText
  }

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.OpeningAudio.{CachedPlaybackRequest, FilePlaybackRequest}
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request, as: TransferRequest

  alias Vxpipe.CallEngine.{
    Error,
    ResolvedCallPlan,
    RoomMixer,
    TextToSpeechRequest,
    TranscriptRouter
  }

  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    ParticipantTransfer,
    CallerIdle,
    ConnectionLifecycle,
    EndCall,
    FirstMessage,
    InputTurns,
    OpeningAudio,
    ParticipantLifecycle,
    ReadinessBinding,
    State,
    Startup,
    StartupReadiness,
    ToolCalls,
    UsageObservations
  }

  @call_timeout 5_000
  @transfer_timeout 122_000

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

  @doc "Captures current resource bindings without querying their dependencies."
  def readiness_binding(room_authority, timeout \\ 1_000) do
    GenServer.call(room_authority, :readiness_binding, timeout)
  end

  def join_participant(room_authority, %JoinParticipant{} = command) do
    GenServer.call(room_authority, {:join_participant, command}, @call_timeout)
  end

  def attach_connection(
        room_authority,
        %AttachConnection{} = command,
        subscriber,
        output_sink,
        room_monitor
      )
      when is_pid(subscriber) and is_reference(room_monitor) do
    GenServer.call(
      room_authority,
      {:attach_connection, command, subscriber, output_sink, room_monitor},
      @call_timeout
    )
  end

  @spec participant_transfer_control(pid(), ParticipantTransferControl.t()) ::
          :ok | {:error, Error.t()}
  def participant_transfer_control(room_authority, %ParticipantTransferControl{} = command) do
    GenServer.call(room_authority, {:participant_transfer_control, command}, @call_timeout)
  end

  def send_text(room_authority, %SendText{} = command) do
    GenServer.call(room_authority, {:send_text, command}, @call_timeout)
  end

  @spec transfer(TransferRequest.t()) ::
          {:ok, map()} | {:error, :rejected | :unavailable}
  def transfer(%TransferRequest{} = request) do
    GenServer.call(
      via(request.tenant_id, request.room_id),
      {:transfer_participant, request},
      @transfer_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def speech_to_text_configuration(room_authority, %AttachConnection{} = command) do
    GenServer.call(room_authority, {:speech_to_text_configuration, command}, @call_timeout)
  end

  def prepare_transfer_speech_to_text(room_authority, %AttachConnection{} = command, attempt_id) do
    GenServer.call(
      room_authority,
      {:prepare_transfer_speech_to_text, command, attempt_id},
      @call_timeout
    )
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

    with {:ok, call_lifecycle} <- StartupReadiness.bind(room_source, incarnation_id),
         {:ok, media_policy_authority} <-
           bind_media_policy_authority(room_source, incarnation_id),
         {:ok, transcript_router} <-
           bind_transcript_router(room_source, incarnation_id, media_policy_authority),
         {:ok, room_mixer} <-
           bind_room_mixer(room_source, incarnation_id, media_policy_authority) do
      state =
        State.new(
          ArchiveRecorder.new(room_source, incarnation_id, options),
          build_snapshot(room_source, incarnation_id, options),
          initial_speech_to_text_runtime(room_source),
          OpeningAudio.new(room_source, Keyword.get(options, :opening_audio)),
          FirstMessage.new(room_source),
          call_lifecycle,
          media_policy_authority,
          transcript_router,
          room_mixer
        )

      state = %{state | readiness_options: ReadinessBinding.options(options)}

      case Startup.start_entries(room_source, options, state) do
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

  def handle_call(:readiness_binding, _from, state),
    do: {:reply, ReadinessBinding.capture(state), state}

  def handle_call(:input_admission, _from, state) do
    {:reply, OpeningAudio.admission(state.opening_audio), state}
  end

  def handle_call({:join_participant, command}, _from, state) do
    ParticipantLifecycle.join(command, state)
  end

  def handle_call(
        {:attach_connection, command, subscriber, output_sink, room_monitor},
        {caller, _tag},
        state
      ) do
    case ParticipantTransfer.attach_connection(
           command,
           caller,
           subscriber,
           output_sink,
           room_monitor,
           state
         ) do
      {:handled, reply} ->
        reply

      :unhandled ->
        case ConnectionLifecycle.attach(
               command,
               caller,
               subscriber,
               output_sink,
               room_monitor,
               state
             ) do
          {:reply, {:ok, _role, _runtime, :main, _input_mode, _output_mode, nil} = reply, state} ->
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
  end

  def handle_call(
        {:participant_transfer_control, %ParticipantTransferControl{} = command},
        {caller, _tag},
        state
      ) do
    ParticipantTransfer.control(command, caller, state)
  end

  def handle_call({:speech_to_text_configuration, command}, {caller, _tag}, state) do
    {:reply, ConnectionLifecycle.speech_to_text_configuration(command, caller, state), state}
  end

  def handle_call({:prepare_transfer_speech_to_text, command, attempt_id}, {caller, _tag}, state) do
    ParticipantTransfer.PrivateSpeech.allocate(command, caller, attempt_id, state)
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

  def handle_call({:transfer_participant, %TransferRequest{} = request}, from, state) do
    ParticipantTransfer.begin(request, from, state)
  end

  @impl true
  def handle_info(
        {:vxpipe_transfer_prepared, reference, %ParticipantTransfer.Preparation{} = preparation},
        state
      )
      when is_reference(reference) do
    ParticipantTransfer.prepared(reference, preparation, state)
  end

  def handle_info(
        {:vxpipe_transfer_prepared, reference,
         %ParticipantTransfer.HumanPreparation{} = preparation},
        state
      )
      when is_reference(reference) do
    ParticipantTransfer.prepared(reference, preparation, state)
  end

  def handle_info({reference, {:ok, capability}}, state)
      when is_reference(reference) and is_map(capability) do
    ParticipantTransfer.restored(reference, capability, state)
  end

  def handle_info({reference, :phase_finished}, state) when is_reference(reference),
    do: {:noreply, state}

  def handle_info({reference, {:error, reason}}, state) when is_reference(reference) do
    ParticipantTransfer.worker_failed(reference, reason, state)
  end

  def handle_info({:vxpipe_participant_transfer_deadline, reference}, state)
      when is_reference(reference) do
    ParticipantTransfer.deadline_elapsed(reference, state)
  end

  def handle_info({:vxpipe_participant_transfer_restoration_deadline, reference}, state)
      when is_reference(reference) do
    ParticipantTransfer.restoration_deadline_elapsed(reference, state)
  end

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

  def handle_info({:vxpipe_usage_observations, capability, observations}, state) do
    {:noreply, UsageObservations.record(state, capability, observations)}
  end

  def handle_info({:vxpipe_telephony_usage_observations, observations}, state) do
    {:noreply, UsageObservations.record_telephony(state, observations)}
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
    {:noreply, ParticipantTransfer.teardown_source(state, capability, context)}
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
    case ParticipantTransfer.text_to_speech_unavailable(capability, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        if OpeningAudio.capability?(state.opening_audio, capability) do
          OpeningAudio.failed(state.opening_audio)
          {:stop, :opening_audio_unavailable, state}
        else
          state = AgentOutput.unavailable(capability, state)
          {:noreply, CallerIdle.reconcile(state)}
        end
    end
  end

  def handle_info({:vxpipe_stt_signal, capability, identity, %Signal{} = signal}, state) do
    {:noreply, InputTurns.speech_to_text(capability, identity, signal, state)}
  end

  def handle_info({:vxpipe_stt_unavailable, capability, identity, _reason}, state) do
    case ParticipantTransfer.speech_to_text_unavailable(capability, identity, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        state = ConnectionLifecycle.speech_to_text_unavailable(capability, identity, state)
        {:noreply, CallerIdle.reconcile(state)}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{text_to_speech_capability: %{monitor: monitor}} = state
      ) do
    ConnectionLifecycle.notify(state.connections, :agent_unavailable)
    {:noreply, %{state | text_to_speech_capability: nil}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case ParticipantTransfer.worker_down(monitor, reason, state) do
      {:handled, state} ->
        {:noreply, state}

      :unhandled ->
        if OpeningAudio.worker_monitor?(state.opening_audio, monitor) do
          OpeningAudio.failed(state.opening_audio)
          {:stop, :opening_audio_unavailable, state}
        else
          state =
            cond do
              Map.has_key?(state.participant_monitors, monitor) ->
                participant_id = Map.fetch!(state.participant_monitors, monitor)
                state = ParticipantLifecycle.remove(monitor, reason, state)
                ParticipantTransfer.promote_connection_after_source_exit(state, participant_id)

              Map.has_key?(state.connection_monitors, monitor) ->
                connection_id = Map.fetch!(state.connection_monitors, monitor)
                state = ConnectionLifecycle.remove(monitor, reason, state)

                case ParticipantTransfer.connection_down(connection_id, state) do
                  {:handled, state} -> state
                  :unhandled -> state
                end

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
  end

  defp room_source(options) do
    case Keyword.fetch(options, :plan) do
      {:ok, %ResolvedCallPlan{} = plan} -> plan
      :error -> Keyword.fetch!(options, :command)
    end
  end

  defp initial_speech_to_text_runtime(%CreateRoom{}), do: :application
  defp initial_speech_to_text_runtime(%ResolvedCallPlan{}), do: %{}

  defp bind_media_policy_authority(%CreateRoom{}, _incarnation_id), do: {:ok, nil}

  defp bind_media_policy_authority(%ResolvedCallPlan{}, incarnation_id) do
    case MediaPolicyAuthority.whereis(incarnation_id) do
      authority when is_pid(authority) -> {:ok, authority}
      nil -> {:error, :media_policy_unavailable}
    end
  end

  defp bind_transcript_router(%CreateRoom{}, _incarnation_id, nil), do: {:ok, nil}

  defp bind_transcript_router(%ResolvedCallPlan{}, incarnation_id, media_policy_authority) do
    case TranscriptRouter.whereis(incarnation_id) do
      router when is_pid(router) ->
        case MediaPolicyAuthority.register_enforcer(media_policy_authority, router) do
          {:ok, _snapshot} -> {:ok, router}
          {:error, _reason} -> {:error, :media_policy_unavailable}
        end

      nil ->
        {:error, :transcript_router_unavailable}
    end
  end

  defp bind_room_mixer(%CreateRoom{}, _incarnation_id, nil), do: {:ok, nil}

  defp bind_room_mixer(%ResolvedCallPlan{}, incarnation_id, media_policy_authority) do
    case RoomMixer.whereis(incarnation_id) do
      mixer when is_pid(mixer) ->
        case MediaPolicyAuthority.register_enforcer(media_policy_authority, mixer) do
          {:ok, _snapshot} -> {:ok, mixer}
          {:error, _reason} -> {:error, :media_policy_unavailable}
        end

      nil ->
        {:error, :room_mixer_unavailable}
    end
  end

  defp handle_text_to_speech_playback(capability, request, status, state) do
    case ParticipantTransfer.playback(capability, request, status, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        opening_result =
          if OpeningAudio.capability?(state.opening_audio, capability) do
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
        if state.room_mixer != nil do
          :ok = RoomMixer.complete_opening(state.room_mixer)
        end

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
