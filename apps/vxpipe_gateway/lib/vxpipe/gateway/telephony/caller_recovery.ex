defmodule Vxpipe.Gateway.Telephony.CallerRecovery do
  @moduledoc "Carrier announcement lifecycle held by the original inbound leg."
  alias Vxpipe.CallEngine.Telephony.{Event, Submission}
  alias Vxpipe.Gateway.Telephony.{CallerRecoveryJournal, IncomingSubmission}

  def handle_info(
        {:caller_media_failed, media, binding},
        %{
          status: :running,
          recovery_journal: nil,
          caller_media: {media, _, true},
          incoming_identity: %{binding: binding}
        } = state
      ),
      do: {:continue, start(state, binding)}

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
    state = %{state | caller_media: nil}

    unexpected? =
      reason not in [:normal, :shutdown, :media_unavailable] and
        not match?({:shutdown, _}, reason)

    if eligible? and unexpected? and state.status == :running and is_nil(state.recovery_journal) do
      {:continue, start(state, state.incoming_identity.binding)}
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

  def handle_info(
        :caller_carrier_deadline,
        %{carrier_ended?: false, recovery_journal: %{}} = state
      ),
      do: {:continue, journal(state, :carrier_unknown)}

  def handle_info({:caller_recovery_expired, token}, %{recovery: %{token: token}} = state),
    do: {:end, record_playback(state, :unknown)}

  def handle_info(
        {:incoming_submission, :playback, worker, result},
        %{playback_worker: {worker, _}, recovery: %{} = recovery} = state
      ) do
    case result do
      {:ok, %Submission{status: status}} when status in [:accepted, :unknown] ->
        {:continue, %{state | recovery: arm_recovery(recovery, 5_150)}}

      {:error, {:telnyx_command_rejected, _}} ->
        {:end, record_playback(state, :failed)}

      _failure ->
        {:end, record_playback(state, :unknown)}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{playback_worker: {worker, monitor}} = state
      ) do
    state = %{
      state
      | playback_worker: nil,
        commands_drained?: state.commands_drained? and reason == :normal
    }

    if reason == :normal or is_nil(state.recovery), do: {:continue, state}, else: {:end, state}
  end

  def handle_info(_message, _state), do: :unhandled

  def watch_media(
        %{incoming_identity: %{binding: %{caller_recovery?: true} = binding}} = state,
        %Event{kind: :media_started}
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
            %{state | caller_media: {pid, Process.monitor(pid), false}}
        end

      [] ->
        state
    end
  end

  def watch_media(state, _event), do: state

  defp start(state, binding) do
    service = state.service
    id = "recovery-" <> binding.client_state_leg_id
    Process.send_after(self(), :caller_carrier_deadline, 60_000)

    journal =
      CallerRecoveryJournal.new(
        state.backend,
        state.claim,
        binding.client_state_leg_id,
        DateTime.add(DateTime.utc_now(), 60, :second)
      )

    state = %{
      state
      | recovery_journal: CallerRecoveryJournal.record(journal, :announcement_requested)
    }

    recovery = arm_recovery(%{id: id, timer: nil}, 5_000)
    state = %{state | recovery: recovery}

    case IncomingSubmission.start(self(), :playback, fn ->
           service.adapter.play_recovery_prompt(
             service.adapter_options,
             binding.provider_call_control_id,
             id
           )
         end) do
      {:ok, pid, ref} ->
        %{state | playback_worker: {pid, ref}}

      _failed ->
        send(self(), {:caller_recovery_expired, recovery.token})
        state
    end
  end

  def record_playback(state, :completed), do: journal(state, :announcement_completed)
  def record_playback(state, :failed), do: journal(state, :announcement_failed)
  def record_playback(state, :unknown), do: journal(state, :announcement_unknown)

  def journal(state, phase),
    do: %{state | recovery_journal: CallerRecoveryJournal.record(state.recovery_journal, phase)}

  defp arm_recovery(recovery, delay) do
    if recovery.timer, do: Process.cancel_timer(recovery.timer)
    token = make_ref()
    timer = Process.send_after(self(), {:caller_recovery_expired, token}, delay)
    Map.merge(recovery, %{token: token, timer: timer})
  end

  def cancel(%{recovery: nil} = state), do: state

  def cancel(state) do
    Process.cancel_timer(state.recovery.timer)
    %{state | recovery: nil}
  end
end
