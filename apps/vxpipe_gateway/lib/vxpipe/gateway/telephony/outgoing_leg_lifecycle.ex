defmodule Vxpipe.Gateway.Telephony.OutgoingLegLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Telephony.Event

  alias Vxpipe.Gateway.Telephony.{
    CarrierCleanup,
    ConfiguredService,
    DialSupervisor,
    EndCommandRetry,
    LegUsage,
    MediaAdmission,
    MediaBinding
  }

  def cancel(%{status: :ended} = state, _reason), do: state
  def cancel(%{status: :failed, media_reserved?: false} = state, _reason), do: state

  def cancel(state, reason) do
    if is_nil(state.cleanup) and is_nil(state.cancel_reason) and is_nil(state.carrier_control_id) do
      Process.send_after(self(), :retire_unknown, state.service.media_token_ttl_ms)
    end

    if state.media_reserved?, do: MediaAdmission.revoke(state.media_admission, self())
    state = %{state | cancel_reason: state.cancel_reason || reason, pending_media: nil}
    request_end(state)
  end

  def adopted(%{cancel_reason: nil} = state), do: state
  def adopted(state), do: request_end(state)

  def late_answer(%{commands_drained?: false} = state), do: state
  def late_answer(%{status: :ended} = state), do: state
  def late_answer(%{cancel_reason: nil} = state), do: state

  def late_answer(%{end_worker: worker} = state) when not is_nil(worker),
    do: %{state | end_retry?: true}

  def late_answer(state), do: request_end(%{state | end_requested?: false})

  def end_worker_down(state) do
    state = %{state | end_worker: nil}

    cond do
      not state.commands_drained? or state.status == :ended ->
        terminal_end(state)

      state.end_retry? ->
        request_end(%{state | end_retry?: false, end_requested?: false})

      not state.end_accepted? ->
        schedule_end(state)

      true ->
        state
    end
  end

  def retry_end(state, token) do
    case EndCommandRetry.take(state.end_command_retry, token) do
      {:ok, retry} -> request_end(%{state | end_command_retry: retry, end_requested?: false})
      :stale -> state
    end
  end

  def terminal_end(state),
    do: %{
      state
      | end_command_retry: EndCommandRetry.cancel(state.end_command_retry),
        end_retry?: false
    }

  defp request_end(%{commands_drained?: false} = state), do: terminal_end(state)
  defp request_end(%{status: :ended} = state), do: terminal_end(state)
  defp request_end(%{carrier_control_id: nil} = state), do: state
  defp request_end(%{end_worker: worker} = state) when not is_nil(worker), do: state
  defp request_end(%{end_requested?: true} = state), do: state

  defp request_end(state) do
    state = %{state | end_command_retry: EndCommandRetry.cancel(state.end_command_retry)}

    case DialSupervisor.end_leg(
           self(),
           state.service,
           state.leg_id,
           state.carrier_control_id,
           state.cancel_reason
         ) do
      {:ok, worker, monitor} ->
        %{state | end_worker: {worker, monitor}, end_requested?: true, end_accepted?: false}

      {:error, _reason} ->
        schedule_end(state)
    end
  end

  defp schedule_end(state),
    do: %{
      state
      | end_requested?: true,
        end_command_retry: EndCommandRetry.schedule(state.end_command_retry)
    }

  def validate_cleanup(%{cleanup_scope: nil}), do: {:ok, nil}

  def validate_cleanup(state) do
    request = state.request

    expected = %{
      tenant_key: request.tenant_id,
      call_id: request.call_id,
      room_id: request.room_id
    }

    if state.cleanup_scope == expected do
      binding = Map.put(expected, :incarnation_id, request.incarnation_id)

      with :ok <-
             CarrierCleanup.validate_attachment(
               binding,
               :outgoing_leg,
               binding,
               state.cleanup_options
             ),
           do: {:ok, binding}
    else
      {:error, :invalid_cleanup_binding}
    end
  end

  def attach_cleanup(%{cleanup_binding: nil} = state), do: {:ok, state}

  def attach_cleanup(state) do
    attachment =
      CarrierCleanup.attach(
        state.cleanup_binding,
        :outgoing_leg,
        state.cleanup_binding,
        state.cleanup_options
      )

    {result, cleanup} =
      case attachment do
        {:ok, cleanup} -> {:ok, cleanup}
        {:error, reason, cleanup} -> {{:error, reason}, cleanup}
      end

    state = %{state | cleanup: cleanup}
    binding = state.cleanup_binding

    case CallEngine.monitor_room(binding.tenant_key, binding.room_id, binding.incarnation_id) do
      {:ok, monitor} ->
        state = %{state | cleanup_room_monitor: monitor}

        cond do
          result != :ok -> {:error, elem(result, 1), state}
          is_nil(state.usage) -> {:error, :usage_unavailable, state}
          true -> {:ok, state}
        end

      {:error, _} ->
        {:error, :room_unavailable, state}
    end
  end

  def store_final(%{cleanup: nil} = state), do: state

  def store_final(%{usage: %LegUsage{attempt: %{terminal?: true}}} = state) do
    case CarrierCleanup.begin_final(state.cleanup, state.usage) do
      {:ok, cleanup} -> %{state | cleanup: cleanup}
      {:error, _reason, cleanup} -> %{state | cleanup: cleanup}
    end
  end

  def store_final(state), do: state

  def cleanup_message(%{cleanup: nil}, _message), do: :unhandled

  def cleanup_message(state, message) do
    case CarrierCleanup.handle_info(state.cleanup, message) do
      {:handled, cleanup} ->
        state = %{state | cleanup: cleanup}

        state =
          if CarrierCleanup.status(cleanup) == :unavailable,
            do: cancel(state, :call_cancelled),
            else: state

        {:handled, state}

      :unhandled ->
        :unhandled
    end
  end

  def continue_cleanup(state) do
    state = store_final(state)

    proof =
      cond do
        state.status == :ended -> :carrier_ended
        not state.dial_dispatched? -> :not_submitted
        true -> :unknown
      end

    ready? =
      state.cleanup_room_closed? and state.commands_drained? and
        is_nil(state.dial_worker) and is_nil(state.end_worker) and proof != :unknown and
        CarrierCleanup.final_usage_stored?(state.cleanup, state.usage)

    if ready? do
      case CarrierCleanup.acknowledge(state.cleanup, state.usage, proof, true) do
        {:ok, cleanup} -> {:stop, :normal, %{state | cleanup: cleanup}}
        {:error, :cleanup_unavailable, cleanup} -> {:stop, :normal, %{state | cleanup: cleanup}}
        {:error, _reason, cleanup} -> {:noreply, %{state | cleanup: cleanup}}
      end
    else
      {:noreply, state}
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
