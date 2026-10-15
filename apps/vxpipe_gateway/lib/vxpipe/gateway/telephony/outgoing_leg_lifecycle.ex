defmodule Vxpipe.Gateway.Telephony.OutgoingLegLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, DialSupervisor, MediaAdmission, MediaBinding}

  def cancel(%{status: :ended} = state, _reason), do: state
  def cancel(%{status: :failed, media_reserved?: false} = state, _reason), do: state

  def cancel(state, reason) do
    if is_nil(state.cancel_reason) and is_nil(state.carrier_control_id) do
      Process.send_after(self(), :retire_unknown, state.service.media_token_ttl_ms)
    end

    MediaAdmission.revoke(state.media_admission, self())
    state = %{state | cancel_reason: state.cancel_reason || reason, pending_media: nil}
    request_end(state)
  end

  def adopted(%{cancel_reason: nil} = state), do: state
  def adopted(state), do: request_end(state)

  def late_answer(%{cancel_reason: nil} = state), do: state

  def late_answer(%{end_worker: worker} = state) when not is_nil(worker),
    do: %{state | end_retry?: true}

  def late_answer(state), do: request_end(%{state | end_requested?: false})

  def end_worker_down(state) do
    state = %{state | end_worker: nil}

    if state.end_retry? and state.status != :ended,
      do: request_end(%{state | end_retry?: false, end_requested?: false}),
      else: state
  end

  defp request_end(%{carrier_control_id: nil} = state), do: state
  defp request_end(%{end_requested?: true} = state), do: state

  defp request_end(state) do
    case DialSupervisor.end_leg(
           self(),
           state.service,
           state.leg_id,
           state.carrier_control_id,
           state.cancel_reason
         ) do
      {:ok, worker, monitor} ->
        %{state | end_worker: {worker, monitor}, end_requested?: true}

      {:error, _reason} ->
        state
    end
  end

  @spec handle(Event.t(), MediaBinding.t(), ConfiguredService.t(), String.t()) ::
          {:keep, :ok | {:error, :telephony_leg_mismatch}} | {:stop, :ok} | {:cancel, atom()}
  def handle(%Event{} = event, %MediaBinding{} = binding, %ConfiguredService{} = service, _leg_id) do
    if MediaBinding.matches_event?(binding, event),
      do: action(event, service),
      else: {:keep, {:error, :telephony_leg_mismatch}}
  end

  defp action(%Event{kind: :ended}, _service), do: {:stop, :ok}

  defp action(
         %Event{kind: :answering_machine, answering_machine: :machine},
         %ConfiguredService{answering_machine_detection: :detect}
       ),
       do: {:cancel, :answering_machine}

  defp action(%Event{}, _service), do: {:keep, :ok}
end
