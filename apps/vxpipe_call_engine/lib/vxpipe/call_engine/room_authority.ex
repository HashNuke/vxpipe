defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecovery
  alias Vxpipe.CallEngine.RoomAuthority.DiagnosticNotifications, as: Diagnostics

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder

  alias Vxpipe.CallEngine.Command.{
    ContinueAgent,
    CreateRoom,
    ParticipantTransferControl
  }

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.OpeningAudio.{CachedPlaybackRequest, FilePlaybackRequest}
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext
  alias Vxpipe.CallEngine.Tool.Idle.Request, as: IdleRequest
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request, as: TransferRequest

  alias Vxpipe.CallEngine.{
    Error,
    ResolvedCallPlan,
    TextToSpeechRequest
  }

  alias Vxpipe.CallEngine.Room.Snapshot

  alias Vxpipe.CallEngine.RoomAuthority.{
    ActionAnnouncement,
    AgentOutput,
    ParticipantTransfer,
    CallerIdle,
    Client,
    ConnectionLifecycle,
    DiagnosticInputs,
    EndCall,
    FirstMessage,
    InputTurns,
    MediaBindings,
    IdleWait,
    OpeningAudio,
    OutgoingAdmission,
    OutgoingCall,
    ParticipantLifecycle,
    ReadinessBinding,
    State,
    Startup,
    StartupReadiness,
    ToolCalls,
    UsageObservations
  }

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Verdicts, as: TransferVerdicts

  alias Vxpipe.CallEngine.RoomAuthority.STSSourceCutover

  import Vxpipe.CallEngine.RoomAuthority.Playback,
    only: [handle_text_to_speech_playback: 4, handle_asset_opening_audio_playback: 4]

  def start_link(options) do
    {tenant_id, room_id} = room_identity(options)
    name = Client.via(tenant_id, room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  defdelegate snapshot(tenant_id, room_id), to: Client
  defdelegate input_admission(tenant_id, room_id), to: Client
  defdelegate readiness_binding(room, timeout \\ 1_000), to: Client
  defdelegate join_participant(room, command, incarnation \\ nil), to: Client

  defdelegate attach_connection(
                room,
                command,
                subscriber,
                output,
                monitor,
                source_control? \\ false
              ),
              to: Client

  defdelegate participant_transfer_control(room, command), to: Client
  defdelegate send_text(room, command), to: Client
  defdelegate transfer(request), to: Client
  defdelegate announce_hangup(context, text), to: Client
  defdelegate terminal_submission_admission(context), to: Client
  defdelegate record_decisions(tenant_id, room_id, report), to: Client
  defdelegate record_decisions_usage(tenant_id, room_id, observations), to: Client
  defdelegate bind_transfer_verdict(room, entry), to: Client
  defdelegate bind_transfer_verdict(tenant_id, room_id, entry), to: Client
  defdelegate take_transfer_verdict(tenant_id, room_id, key), to: Client
  defdelegate note_transfer_denial(tenant_id, room_id, note), to: Client
  defdelegate idle(request), to: Client
  defdelegate speech_to_text_configuration(room, command), to: Client
  defdelegate prepare_transfer_speech_to_text(room, command, attempt_id), to: Client
  defdelegate prepare_transfer_media(room, command, attempt_id), to: Client
  defdelegate bind_speech_to_text(room, command, subscriber, capability, ingress), to: Client
  defdelegate detach_connection(room, command, subscriber), to: Client

  @impl true
  def init(options) do
    room_source = room_source(options)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    with {:ok, call_lifecycle} <- StartupReadiness.bind(room_source, incarnation_id),
         {:ok, media_policy_authority} <-
           MediaBindings.bind_media_policy_authority(room_source, incarnation_id),
         {:ok, transcript_router} <-
           MediaBindings.bind_transcript_router(
             room_source,
             incarnation_id,
             media_policy_authority
           ),
         {:ok, room_mixer} <-
           MediaBindings.bind_room_mixer(room_source, incarnation_id, media_policy_authority) do
      state =
        State.new(
          ArchiveRecorder.new(room_source, incarnation_id, options),
          Snapshot.new(room_source, incarnation_id, options),
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

      case OutgoingAdmission.start_entries(room_source, options, state) do
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
  def handle_call({:diagnostic_inputs, cursor, limit}, _from, state),
    do: {:reply, DiagnosticInputs.read(state, cursor, limit), state}

  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:end_call, incarnation}, _from, state),
    do: EndCall.remote_hangup(incarnation, state)

  def handle_call({:hangup_call, incarnation}, _from, state),
    do: EndCall.api_hangup(incarnation, state)

  def handle_call({operation, _incarnation, _token} = request, from, state)
      when operation in [:admit_outgoing, :cancel_outgoing, :admit_call, :cancel_call_admission],
      do: OutgoingAdmission.control(request, from, state)

  def handle_call(:readiness_binding, _from, state),
    do: {:reply, ReadinessBinding.capture(state), state}

  def handle_call({:mcp_initialization_budget, activation, preparer, deadline}, _from, state),
    do: {:reply, Startup.mcp_budget(state, activation, preparer, deadline), state}

  def handle_call(:input_admission, _from, state) do
    admission =
      if OutgoingAdmission.pending?(state) or
           (state.startup != nil and not state.startup_ready?),
         do: :opening_audio,
         else: OpeningAudio.admission(state.opening_audio)

    {:reply, admission, state}
  end

  def handle_call({:join_participant, command, incarnation}, _from, state) do
    ParticipantLifecycle.join(command, state, incarnation) |> Diagnostics.notify()
  end

  def handle_call(
        {:attach_connection, command, subscriber, output_sink, room_monitor, source_control?},
        {caller, _tag},
        state
      ) do
    case ParticipantTransfer.attach_connection(
           command,
           caller,
           subscriber,
           output_sink,
           room_monitor,
           source_control?,
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
               source_control?,
               state
             ) do
          {:reply, {:ok, _role, _runtime, :main, _input_mode, _output_mode, nil} = reply, state} ->
            case StartupReadiness.begin_connection_startup(command, state) do
              {:ok, state} ->
                {:reply, reply, CallerIdle.reconcile(state)}

              {:error, %Error{code: code} = error} ->
                {:stop, code, {:error, error}, state}
            end

          other ->
            other
        end
    end
    |> Diagnostics.notify()
  end

  def handle_call(
        {:participant_transfer_control, %ParticipantTransferControl{} = command},
        {caller, _tag},
        state
      ) do
    ParticipantTransfer.control(command, caller, state) |> Diagnostics.notify()
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
    |> Diagnostics.notify()
  end

  def handle_call({:detach_connection, command, subscriber}, {caller, _tag}, state) do
    case ConnectionLifecycle.detach(command, caller, subscriber, state) do
      {:reply, reply, state} -> {:reply, reply, CallerIdle.reconcile(state)}
    end
    |> Diagnostics.notify()
  end

  def handle_call({:send_text, command}, {caller, _tag}, state) do
    InputTurns.accept_text(command, caller, state)
  end

  def handle_call({:transfer_participant, %TransferRequest{} = request}, from, state) do
    case ParticipantTransfer.begin(request, from, state) do
      {:noreply, state} -> {:noreply, CallerIdle.reconcile(state)}
      reply -> reply
    end
  end

  def handle_call({:bind_transfer_verdict, entry}, _from, %State{} = state) when is_map(entry) do
    case TransferVerdicts.bind(state, entry) do
      {:ok, next} -> {:reply, :ok, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:take_transfer_verdict, key}, _from, %State{} = state) do
    {:reply, TransferVerdicts.peek(state, key), state}
  end

  def handle_call({:announce_hangup, context, text}, from, state),
    do: ActionAnnouncement.hangup(context, text, from, state)

  def handle_call({:terminal_submission_admission, context}, _from, state),
    do: {:reply, __MODULE__.CallerAnswer.terminal_admission(state, context), state}

  def handle_call({:idle, %IdleRequest{} = request}, from, state) do
    case IdleWait.begin(request, from, state) do
      {:noreply, state} -> {:noreply, CallerIdle.reconcile(state)}
      reply -> reply
    end
  end

  @impl true
  def handle_info({:announcement_deadline, id}, state), do: ActionAnnouncement.deadline(id, state)

  def handle_info({:decisions_report, report}, %State{} = state) when is_map(report) do
    {:noreply, Vxpipe.CallEngine.RoomAuthority.DecisionsPublication.record(state, report)}
  end

  def handle_info({:decisions_late_usage, observations}, %State{} = state)
      when is_list(observations) do
    {:noreply,
     Vxpipe.CallEngine.RoomAuthority.DecisionsPublication.record_usage(state, observations)}
  end

  def handle_info({:note_transfer_denial, note}, %State{} = state) when is_map(note) do
    {:noreply, ParticipantTransfer.note_denied(state, note)}
  end

  def handle_info(
        {[:alias | id], _} = message,
        %{action_announcement: %{request_id: id}} = state
      ),
      do: ActionAnnouncement.response(message, state)

  def handle_info(
        {:DOWN, id, :process, _, _} = message,
        %{action_announcement: %{request_id: id}} = state
      ),
      do: ActionAnnouncement.response(message, state)

  def handle_info({:vxpipe_idle_wait_deadline, token, phase}, state) do
    state = IdleWait.deadline(token, phase, state)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle_info(
        {[:alias | response_ref], _response} = message,
        %State{source_cutover: %{request_id: request_id}} = state
      )
      when response_ref == request_id,
      do: {:noreply, STSSourceCutover.handle_response(message, state)}

  def handle_info(
        {[:alias | response_ref], _response} = message,
        %State{source_cutover: %{late_request_id: request_id, phase: :failed}} = state
      )
      when response_ref == request_id,
      do: {:noreply, STSSourceCutover.handle_response(message, state)}

  def handle_info({:vxpipe_sts_source_cutover_timeout, token}, state) do
    {:noreply, STSSourceCutover.timeout(token, state)}
  end

  def handle_info(
        {:vxpipe_stt_source_origin_invalidated, ingress, identity, origin, _revision,
         producer_generation},
        state
      ) do
    if ConnectionLifecycle.current_source_ingress?(state, ingress, identity) do
      old_generation =
        if is_reference(producer_generation),
          do: producer_generation,
          else: if(is_map(origin), do: Map.get(origin, :allocation_generation))

      {:noreply, STSSourceCutover.hold(state, :policy, old_generation)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {ref, {:startup_prepared, result}},
        %{startup: %{task: %Task{ref: ref}}} = state
      ),
      do:
        StartupReadiness.preparation_result(ref, result, state)
        |> Diagnostics.notify()

  def handle_info(
        {ref, {:opening_prepared, result}},
        %{startup: %{opening_task: %Task{ref: ref}}} = state
      ),
      do:
        StartupReadiness.opening_preparation_result(ref, result, state)
        |> Diagnostics.notify()

  def handle_info({reference, {:startup_output, id, result}}, state),
    do:
      StartupReadiness.reply(StartupReadiness.output_result(reference, id, result, state), state)
      |> Diagnostics.notify()

  def handle_info({reference, {:outgoing_submitted, result}}, state),
    do: OutgoingCall.submitted(reference, result, state) |> Diagnostics.notify()

  def handle_info({:vxpipe_outbound_leg, token, owner, event}, state),
    do: OutgoingCall.report(token, owner, event, state) |> Diagnostics.notify()

  def handle_info({:vxpipe_call_lifecycle_timer, token, :outgoing_ring}, state),
    do: OutgoingCall.timeout(token, state)

  def handle_info({reference, {:startup_ready, result}}, state),
    do:
      StartupReadiness.reply(StartupReadiness.room_result(reference, result, state), state)
      |> Diagnostics.notify()

  def handle_info({reference, {:startup_release, result}}, state),
    do:
      StartupReadiness.reply(StartupReadiness.release_result(reference, result, state), state)
      |> Diagnostics.notify()

  def handle_info({:vxpipe_wait_playback, player, episode, status}, %{startup: startup} = state)
      when startup != nil,
      do:
        StartupReadiness.reply(StartupReadiness.playback(player, episode, status, state), state)
        |> Diagnostics.notify()

  def handle_info({:vxpipe_opening_audio_ready, gate}, state) do
    opening = OpeningAudio.ready(state.opening_audio, gate)

    StartupReadiness.reply(
      StartupReadiness.opening_changed(%{state | opening_audio: opening}),
      state
    )
    |> Diagnostics.notify()
  end

  def handle_info({:vxpipe_transfer_progress, reference, progress}, state),
    do: ParticipantTransfer.progress(reference, progress, state) |> Diagnostics.notify()

  def handle_info({:vxpipe_transfer_handoff_result, reference, stage, result}, state),
    do:
      ParticipantTransfer.HumanHandoff.handoff_result(reference, stage, result, state)
      |> Diagnostics.notify()

  def handle_info(
        {:vxpipe_transfer_prepared, reference, %ParticipantTransfer.Preparation{} = preparation},
        state
      )
      when is_reference(reference) do
    ParticipantTransfer.prepared(reference, preparation, state)
    |> Diagnostics.notify()
  end

  def handle_info(
        {:vxpipe_transfer_prepared, reference,
         %ParticipantTransfer.HumanPreparation{} = preparation},
        state
      )
      when is_reference(reference) do
    ParticipantTransfer.prepared(reference, preparation, state)
    |> Diagnostics.notify()
  end

  def handle_info({reference, :phase_finished}, state) when is_reference(reference),
    do: {:noreply, state}

  def handle_info({reference, {:error, reason}}, state) when is_reference(reference) do
    ParticipantTransfer.worker_failed(reference, reason, state)
    |> Diagnostics.notify()
  end

  def handle_info({:vxpipe_participant_transfer_deadline, reference}, state)
      when is_reference(reference) do
    ParticipantTransfer.deadline_elapsed(reference, state) |> Diagnostics.notify()
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

  def handle_info({:vxpipe_sts_platform_effect, capability, scope, :hangup}, state),
    do: EndCall.sts_tool_hangup(capability, scope, state)

  def handle_info({:vxpipe_platform_effect, capability, context, :announced_hangup}, state),
    do: ActionAnnouncement.settle_hangup(capability, context, state)

  def handle_info({:vxpipe_platform_effect, capability, context, :hangup}, state),
    do: EndCall.tool_hangup(capability, context, state)

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
      when status in [:started, :completed, :discarded] do
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

  def handle_info({:vxpipe_tts_unavailable, capability, _reason}, state),
    do: Vxpipe.CallEngine.RoomAuthority.Playback.unavailable(capability, state)

  def handle_info(
        {:vxpipe_stt_signal, capability, identity, %Signal{} = signal, observation},
        state
      ) do
    {:noreply, InputTurns.speech_to_text(capability, identity, signal, state, observation)}
  end

  require CallerSpeechRecovery

  def handle_info(message, state) when CallerSpeechRecovery.recovery_message?(message),
    do: CallerSpeechRecovery.handle(message, state)

  def handle_info({:vxpipe_stt_signal, capability, identity, %Signal{} = signal}, state) do
    {:noreply, InputTurns.speech_to_text(capability, identity, signal, state)}
  end

  def handle_info(message, state)
      when elem(message, 0) in [
             :vxpipe_sts_ready,
             :vxpipe_remote_tools_ready,
             :vxpipe_sts_readiness_timeout,
             :vxpipe_sts_activity_origin_changed,
             :vxpipe_sts_speech_started,
             :vxpipe_sts_input_event,
             :vxpipe_sts_turn_started,
             :vxpipe_sts_agent_transcript,
             :vxpipe_sts_reseed_room_barrier,
             :vxpipe_sts_turn_completed,
             :vxpipe_sts_interrupted,
             :vxpipe_sts_tool_event,
             :vxpipe_sts_tool_completion,
             :vxpipe_sts_output_stt_unavailable,
             :vxpipe_sts_unavailable
           ] do
    Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Events.handle(message, state)
  end

  def handle_info({:vxpipe_stt_unavailable, capability, identity, _reason}, state) do
    case ParticipantTransfer.speech_to_text_unavailable(capability, identity, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        state = ConnectionLifecycle.speech_to_text_unavailable(capability, identity, state)
        {:noreply, CallerIdle.reconcile(state)}
    end
    |> Diagnostics.notify()
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state),
    do:
      Vxpipe.CallEngine.RoomAuthority.ProcessDown.handle(monitor, reason, state)
      |> Diagnostics.notify()

  def handle_info({:timeout, timer, {:transfer_verdict, key}}, state),
    do: {:noreply, TransferVerdicts.expire(state, key, timer)}

  def handle_info(_message, state), do: {:noreply, state}

  defp room_source(options) do
    case Keyword.fetch(options, :plan) do
      {:ok, %ResolvedCallPlan{} = plan} -> plan
      :error -> Keyword.fetch!(options, :command)
    end
  end

  defp initial_speech_to_text_runtime(%CreateRoom{}), do: %{}
  defp initial_speech_to_text_runtime(%ResolvedCallPlan{}), do: %{}

  defp room_identity(options) do
    source = room_source(options)
    {source.tenant_id, source.room_id}
  end
end
