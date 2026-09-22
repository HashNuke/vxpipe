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
    SpeechToSpeech,
    State,
    Startup,
    StartupReadiness,
    ToolCalls,
    UsageObservations
  }

  import Vxpipe.CallEngine.RoomAuthority.Playback,
    only: [handle_text_to_speech_playback: 4, handle_asset_opening_audio_playback: 4]

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

  def prepare_transfer_media(room_authority, %AttachConnection{} = command, attempt_id) do
    GenServer.call(room_authority, {:prepare_transfer_media, command, attempt_id}, @call_timeout)
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

      policy_monitor = if media_policy_authority, do: Process.monitor(media_policy_authority)

      state = %{
        state
        | readiness_options: ReadinessBinding.options(options),
          media_policy_monitor: policy_monitor
      }

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
    admission =
      if state.startup != nil and not state.startup_ready?,
        do: :opening_audio,
        else: OpeningAudio.admission(state.opening_audio)

    {:reply, admission, state}
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

  def handle_call({:prepare_transfer_media, command, attempt_id}, {caller, _tag}, state) do
    ParticipantTransfer.PrivateMedia.allocate(command, caller, attempt_id, state)
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
        {ref, {:startup_prepared, result}},
        %{startup: %{task: %Task{ref: ref}}} = state
      ),
      do: StartupReadiness.preparation_result(ref, result, state)

  def handle_info(
        {ref, {:opening_prepared, result}},
        %{startup: %{opening_task: %Task{ref: ref}}} = state
      ),
      do: StartupReadiness.opening_preparation_result(ref, result, state)

  def handle_info({reference, {:startup_output, id, result}}, state),
    do:
      StartupReadiness.reply(StartupReadiness.output_result(reference, id, result, state), state)

  def handle_info({reference, {:startup_ready, result}}, state),
    do: StartupReadiness.reply(StartupReadiness.room_result(reference, result, state), state)

  def handle_info({reference, {:startup_release, result}}, state),
    do: StartupReadiness.reply(StartupReadiness.release_result(reference, result, state), state)

  def handle_info({:vxpipe_wait_playback, player, episode, status}, %{startup: startup} = state)
      when startup != nil,
      do: StartupReadiness.reply(StartupReadiness.playback(player, episode, status, state), state)

  def handle_info({:vxpipe_opening_audio_ready, gate}, state) do
    opening = OpeningAudio.ready(state.opening_audio, gate)

    StartupReadiness.reply(
      StartupReadiness.opening_changed(%{state | opening_audio: opening}),
      state
    )
  end

  def handle_info({:vxpipe_transfer_progress, reference, progress}, state),
    do: ParticipantTransfer.progress(reference, progress, state)

  def handle_info({:vxpipe_transfer_handoff_result, reference, stage, result}, state),
    do: ParticipantTransfer.HumanHandoff.handoff_result(reference, stage, result, state)

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

  def handle_info({reference, :phase_finished}, state) when is_reference(reference),
    do: {:noreply, state}

  def handle_info({reference, {:error, reason}}, state) when is_reference(reference) do
    ParticipantTransfer.worker_failed(reference, reason, state)
  end

  def handle_info({:vxpipe_participant_transfer_deadline, reference}, state)
      when is_reference(reference) do
    ParticipantTransfer.deadline_elapsed(reference, state)
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
      StartupReadiness.failed(state, :opening_audio_unavailable)
      {:stop, :opening_audio_unavailable, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_tts_unavailable, capability, _reason},
        %{startup: startup, startup_ready?: false, text_to_speech_capability: %{pid: capability}} =
          state
      )
      when startup != nil,
      do: StartupReadiness.reply({:error, :text_to_speech_unavailable}, state)

  def handle_info({:vxpipe_tts_unavailable, capability, _reason}, state) do
    case ParticipantTransfer.text_to_speech_unavailable(capability, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        if OpeningAudio.capability?(state.opening_audio, capability) do
          OpeningAudio.failed(state.opening_audio)
          StartupReadiness.failed(state, :opening_audio_unavailable)
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

  def handle_info({:vxpipe_sts_ready, capability}, state) do
    if SpeechToSpeech.current?(state, capability) do
      state = SpeechToSpeech.handle_ready(state, capability)
      StartupReadiness.reply(StartupReadiness.ready(state), state)
    else
      {:noreply, state}
    end
  end

  def handle_info({:vxpipe_sts_speech_started, capability, agent_id, turn}, state) do
    {:noreply, SpeechToSpeech.handle_speech_started(state, capability, agent_id, turn)}
  end

  def handle_info({:vxpipe_sts_input_transcript, capability, human_id, text, turn, final?}, state)
      when is_boolean(final?) do
    {:noreply,
     SpeechToSpeech.handle_input_transcript(state, capability, human_id, text, turn, final?)}
  end

  def handle_info({:vxpipe_sts_input_transcript, capability, human_id, text, turn}, state) do
    {:noreply, SpeechToSpeech.handle_input_transcript(state, capability, human_id, text, turn)}
  end

  def handle_info({:vxpipe_sts_turn_started, capability, agent_id, turn}, state) do
    {:noreply, SpeechToSpeech.handle_turn_started(state, capability, agent_id, turn)}
  end

  def handle_info({:vxpipe_sts_agent_transcript, capability, agent_id, text, turn, played}, state) do
    {:noreply,
     SpeechToSpeech.handle_agent_transcript(state, capability, agent_id, text, turn, played)}
  end

  def handle_info({:vxpipe_sts_turn_completed, capability, agent_id, turn}, state) do
    {:noreply,
     CallerIdle.reconcile(SpeechToSpeech.handle_turn_completed(state, capability, agent_id, turn))}
  end

  def handle_info({:vxpipe_sts_interrupted, capability, agent_id, turn, played, prefix}, state) do
    {:noreply,
     CallerIdle.reconcile(
       SpeechToSpeech.handle_interrupted(state, capability, agent_id, turn, played, prefix)
     )}
  end

  def handle_info(
        {:vxpipe_sts_tool_call, capability, agent_id, call_ref, turn, name, args},
        state
      ) do
    {:noreply,
     SpeechToSpeech.handle_tool_call(state, capability, agent_id, call_ref, turn, name, args)}
  end

  def handle_info({:vxpipe_sts_tool_cancelled, capability, agent_id, call_ref}, state) do
    {:noreply, SpeechToSpeech.handle_tool_cancelled(state, capability, agent_id, call_ref)}
  end

  def handle_info({:vxpipe_sts_tool_executed, capability, call_ref, outcome}, state) do
    {:noreply, SpeechToSpeech.handle_tool_executed(state, capability, call_ref, outcome)}
  end

  def handle_info({:vxpipe_sts_tool_timeout, capability, call_ref}, state) do
    {:noreply, SpeechToSpeech.handle_tool_timeout(state, capability, call_ref)}
  end

  # Output-STT recognition problems are observability only at the room
  # boundary: the turn outcome (completed/interrupted with or without text)
  # already settles through the dedicated turn messages above.
  def handle_info({:vxpipe_sts_output_stt_unavailable, _capability, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({:vxpipe_sts_unavailable, capability, reason}, state) do
    state = SpeechToSpeech.handle_unavailable(state, capability, reason)
    {:noreply, CallerIdle.reconcile(state)}
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
        %{startup: startup, startup_ready?: false, text_to_speech_capability: %{monitor: monitor}} =
          state
      )
      when startup != nil,
      do: StartupReadiness.reply({:error, :text_to_speech_unavailable}, state)

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{text_to_speech_capability: %{monitor: monitor}} = state
      ) do
    ConnectionLifecycle.notify(state.connections, :agent_unavailable)
    {:noreply, %{state | text_to_speech_capability: nil}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state),
    do: Vxpipe.CallEngine.RoomAuthority.ProcessDown.handle(monitor, reason, state)

  defp room_source(options) do
    case Keyword.fetch(options, :plan) do
      {:ok, %ResolvedCallPlan{} = plan} -> plan
      :error -> Keyword.fetch!(options, :command)
    end
  end

  defp initial_speech_to_text_runtime(%CreateRoom{}), do: %{}
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

  defp begin_connection_startup(command, %{startup: startup, startup_ready?: false} = state)
       when startup != nil,
       do: StartupReadiness.connection_attached(command, state)

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
