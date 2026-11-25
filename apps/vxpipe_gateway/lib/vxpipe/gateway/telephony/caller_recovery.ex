defmodule Vxpipe.Gateway.Telephony.CallerRecovery do
  @moduledoc "Carrier announcement lifecycle held by the original inbound leg."
  alias Vxpipe.CallEngine.Telephony.{Event, Submission}
  alias Vxpipe.Gateway.Telephony.{CallerRecoveryJournal, CallerRecoveryPeer, IncomingSubmission}

  @exit_budget_ms 60_000
  @end_reserve_ms 5_000
  @command_budget_ms 5_000
  @clip_budget_ms 5_150

  def request_hangup(binding) do
    case Registry.lookup(Vxpipe.Gateway.Telephony.LegRegistry, {:caller_recovery, binding}) do
      [{leg, _}] ->
        send(leg, {:hangup_caller_recovery, binding})
        :requested

      [] ->
        :unavailable
    end
  end

  def handle_info({:hangup_caller_recovery, binding}, %{recovery: %{binding: binding}} = state) do
    {:end, abandon_transfer(state), :api_hangup}
  end

  def handle_info(
        {:caller_stream_stopped, socket, stream},
        %{caller_stream: {socket, stream}, caller_media: {_media, monitor, _}} = state
      ) do
    Process.demonitor(monitor, [:flush])
    {:continue, %{state | caller_media: nil, caller_stream: nil}}
  end

  def handle_info(
        {:caller_media_failed, media, binding, reason},
        %{
          status: :running,
          recovery_journal: nil,
          caller_media: {media, _, true},
          incoming_identity: %{binding: binding}
        } = state
      )
      when reason in [
             :speech_to_text_unavailable,
             :text_to_speech_unavailable,
             :agent_unavailable
           ],
      do: {:continue, start(state, binding, reason)}

  def handle_info(
        {:caller_media_eligible, media, eligible?},
        %{caller_media: {media, ref, _}} = state
      )
      when is_boolean(eligible?),
      do: {:continue, %{state | caller_media: {media, ref, eligible?}}}

  def handle_info(
        {:DOWN, ref, :process, media, reason},
        %{caller_media: {media, ref, eligible?}} = state
      ) do
    state = %{state | caller_media: nil, caller_stream: nil}

    unexpected? =
      reason not in [:normal, :shutdown, :media_unavailable] and
        not match?({:shutdown, _}, reason)

    if eligible? and unexpected? and state.status == :running and is_nil(state.recovery_journal) do
      {:continue, start(state, state.incoming_identity.binding, :media_process_lost)}
    else
      {:continue, state}
    end
  end

  def handle_info({:retry_recovery_journal, token}, state) do
    {:continue,
     %{
       state
       | recovery_journal: CallerRecoveryJournal.retry(state.recovery_journal, token)
     }}
  end

  def handle_info(:caller_carrier_deadline, %{recovery: %{phase: :bridged}} = state),
    do: {:continue, state}

  def handle_info(
        {:recovery_peer, peer, :bridged},
        %{recovery: %{peer: peer, phase: phase} = r} = state
      )
      when phase in [:ringing, :reconciling] do
    Process.cancel_timer(r.timer)

    {:continue,
     journal(
       %{state | recovery: %{r | phase: :bridged, timer: nil, token: nil}},
       :transfer_bridged
     )}
  end

  def handle_info(
        {:recovery_peer, peer, {:ended, _}},
        %{recovery: %{peer: peer, phase: :bridged}} = state
      ),
      do: {:end, state}

  def handle_info(
        {:recovery_peer, peer, outcome},
        %{recovery: %{peer: peer, phase: phase}} = state
      )
      when phase in [:ringing, :reconciling] do
    classification =
      case outcome do
        {:ended, :rejected} -> :transfer_rejected
        {:ended, :busy} -> :transfer_busy
        {:ended, reason} when reason in [:no_answer, :timeout] -> :transfer_unanswered
        _ -> :transfer_failed
      end

    fallback(journal(state, classification))
  end

  def handle_info(
        {:DOWN, ref, :process, peer, _},
        %{recovery: %{peer: peer, peer_ref: ref, phase: phase}} = state
      ) do
    case phase do
      :bridged -> {:end, journal(state, :transfer_unknown)}
      phase when phase in [:ringing, :reconciling] -> {:end, journal(state, :transfer_unknown)}
      _ -> fallback(state)
    end
  end

  def handle_info(
        {:caller_recovery_expired, token},
        %{recovery: %{token: token, phase: :ringing} = r} = state
      ),
      do: {:continue, %{state | recovery: arm_recovery(%{r | phase: :reconciling}, 5_000)}}

  def handle_info(
        {:caller_recovery_expired, token},
        %{recovery: %{token: token, phase: :reconciling}} = state
      ),
      do: {:end, journal(state, :transfer_unknown)}

  def handle_info(
        :caller_carrier_deadline,
        %{carrier_ended?: false, recovery_journal: %{}} = state
      ),
      do: {:continue, journal(state, :carrier_unknown)}

  def handle_info({:caller_recovery_expired, token}, %{recovery: %{token: token}} = state),
    do: playback_result(state, :unknown)

  def handle_info(
        {:incoming_submission, :playback, worker, result},
        %{playback_worker: {worker, _}, recovery: %{phase: :submitting} = recovery} = state
      ) do
    case result do
      {:ok, %Submission{status: status}} when status in [:accepted, :unknown] ->
        {:continue,
         %{
           state
           | recovery: arm_recovery(%{recovery | phase: :playing}, clip_budget(recovery.clip))
         }}

      {:error, {:telnyx_command_rejected, _}} ->
        playback_result(state, :failed)

      _failure ->
        playback_result(state, :unknown)
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{playback_monitors: monitors} = state
      )
      when :erlang.map_get(worker, monitors) == monitor do
    state = %{
      state
      | playback_monitors: Map.delete(monitors, worker),
        playback_worker:
          if(state.playback_worker == {worker, monitor}, do: nil, else: state.playback_worker),
        commands_drained?: state.commands_drained? and reason == :normal
    }

    # The carrier may already be playing the clip. Its signed completion or
    # the existing deadline can settle the attempt after observer loss.
    {:continue, state}
  end

  def handle_info(_message, _state), do: :unhandled

  def watch_media(
        %{incoming_identity: %{binding: %{caller_recovery?: true} = binding}} = state,
        %Event{kind: :media_started, stream_id: stream},
        socket
      ) do
    case Registry.lookup(
           Vxpipe.Gateway.Media.Registry,
           {:telephony_media_session, binding.client_state_leg_id}
         ) do
      [{pid, _}] ->
        case state.caller_media do
          {^pid, _, _} ->
            state

          prior ->
            if prior, do: Process.demonitor(elem(prior, 1), [:flush])

            %{
              state
              | caller_media: {pid, Process.monitor(pid), false},
                caller_stream: {socket, stream}
            }
        end

      [] ->
        state
    end
  end

  def watch_media(state, _event, _socket), do: state

  defp start(state, binding, reason) do
    deadline = System.monotonic_time(:millisecond) + @exit_budget_ms
    Process.send_after(self(), :caller_carrier_deadline, deadline, abs: true)

    journal =
      CallerRecoveryJournal.new(
        state.backend,
        state.claim,
        binding.client_state_leg_id,
        DateTime.add(DateTime.utc_now(), @exit_budget_ms, :millisecond),
        reason
      )

    anchor = %{
      tenant_key: binding.tenant_id,
      call_id: binding.call_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id
    }

    {:ok, _} =
      Registry.register(
        Vxpipe.Gateway.Telephony.LegRegistry,
        {:caller_recovery, anchor},
        :carrier_owner
      )

    recovery = %{
      binding: anchor,
      id: nil,
      phase: nil,
      clip: nil,
      deadline: deadline,
      timer: nil,
      token: nil,
      peer: nil,
      peer_ref: nil
    }

    state = %{state | recovery: recovery, recovery_journal: journal}

    case recovery_destination(state) do
      nil ->
        play(state, :callback)

      participant ->
        case CallerRecoveryPeer.prepare(state, participant) do
          {:ok, peer} ->
            play(
              %{state | recovery: %{recovery | peer: peer, peer_ref: Process.monitor(peer)}},
              :transfer
            )

          _unavailable ->
            play(state, :callback)
        end
    end
  end

  defp recovery_destination(state) do
    plan = state.claim.call.plan
    caller = Map.fetch!(plan.participants, state.claim.participant_ref)

    with key when is_binary(key) <- Map.get(plan.transfer_policy || %{}, :recovery_destination),
         %{kind: :human, telephony_service: service, connection: %{mode: :dial, number: to}} =
           target
         when is_binary(to) <- Map.get(plan.participants, key),
         true <- service != nil and service == caller.telephony_service,
         true <-
           is_binary(state.service.outbound_number) and
             to not in [
               state.initial_event.from,
               state.initial_event.to,
               state.service.outbound_number
             ] do
      target
    else
      _ -> nil
    end
  end

  defp play(state, clip) do
    phase =
      if clip == :callback, do: :announcement_requested, else: :transfer_announcement_requested

    id = CallerRecoveryJournal.command_id(state.recovery_journal, phase)

    recovery =
      arm_recovery(%{state.recovery | id: id, phase: :submitting, clip: clip}, @command_budget_ms)

    state = journal(%{state | recovery: recovery}, phase)

    if clip == :transfer and not CallerRecoveryJournal.settled?(state.recovery_journal) do
      play(drop_peer(state), :callback)
    else
      submit_playback(state)
    end
  end

  defp submit_playback(state) do
    service = state.service
    recovery = state.recovery
    control = state.incoming_identity.binding.provider_call_control_id

    case IncomingSubmission.start(self(), :playback, fn ->
           if recovery.clip == :callback,
             do:
               service.adapter.play_recovery_prompt(service.adapter_options, control, recovery.id),
             else:
               service.adapter.play_recovery_prompt(
                 service.adapter_options,
                 control,
                 recovery.id,
                 :transfer
               )
         end) do
      {:ok, pid, ref} ->
        %{
          state
          | playback_worker: {pid, ref},
            playback_monitors: Map.put(state.playback_monitors, pid, ref)
        }

      _failed ->
        send(self(), {:caller_recovery_expired, recovery.token})
        state
    end
  end

  def playback_result(%{recovery: %{phase: phase}} = state, _)
      when phase not in [:submitting, :playing], do: {:continue, state}

  def playback_result(%{recovery: %{clip: :callback}} = state, outcome) do
    phase = %{
      completed: :announcement_completed,
      failed: :announcement_failed,
      unknown: :announcement_unknown
    }

    {:end, journal(state, Map.fetch!(phase, outcome))}
  end

  def playback_result(state, outcome) do
    phase = %{
      completed: :transfer_announcement_completed,
      failed: :transfer_announcement_failed,
      unknown: :transfer_announcement_unknown
    }

    state = journal(state, Map.fetch!(phase, outcome))

    if outcome == :completed do
      state = journal(state, :transfer_requested)

      if CallerRecoveryJournal.settled?(state.recovery_journal) do
        CallerRecoveryPeer.dial(state.recovery.peer)

        {:continue,
         %{state | recovery: arm_recovery(%{state.recovery | phase: :ringing}, 20_000)}}
      else
        fallback(state)
      end
    else
      fallback(state)
    end
  end

  defp fallback(state) do
    state = drop_peer(state)

    if state.recovery.deadline - System.monotonic_time(:millisecond) >=
         @end_reserve_ms + @clip_budget_ms do
      {:continue, play(state, :callback)}
    else
      {:end, state}
    end
  end

  defp drop_peer(%{recovery: %{peer: nil}} = state), do: state

  defp drop_peer(%{recovery: r} = state) do
    Process.demonitor(r.peer_ref, [:flush])
    CallerRecoveryPeer.abandon(r.peer)
    %{state | recovery: %{r | peer: nil, peer_ref: nil}}
  end

  defp clip_budget(:transfer), do: 4_140
  defp clip_budget(:callback), do: @clip_budget_ms

  def journal(state, phase),
    do: %{state | recovery_journal: CallerRecoveryJournal.record(state.recovery_journal, phase)}

  defp arm_recovery(recovery, delay) do
    if recovery.timer, do: Process.cancel_timer(recovery.timer)
    token = make_ref()

    expires =
      min(System.monotonic_time(:millisecond) + delay, recovery.deadline - @end_reserve_ms)

    timer = Process.send_after(self(), {:caller_recovery_expired, token}, expires, abs: true)
    Map.merge(recovery, %{token: token, timer: timer})
  end

  def abandon_transfer(%{recovery: %{peer: peer, phase: phase}} = state)
      when is_pid(peer) and phase != :bridged,
      do: journal(state, :transfer_abandoned)

  def abandon_transfer(state), do: state

  def cancel(%{recovery: nil} = state), do: state

  def cancel(state) do
    if state.recovery.timer, do: Process.cancel_timer(state.recovery.timer)
    state = drop_peer(state)
    %{state | recovery: nil}
  end
end
