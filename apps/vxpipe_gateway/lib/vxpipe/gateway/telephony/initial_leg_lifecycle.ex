defmodule Vxpipe.Gateway.Telephony.InitialLegLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}
  alias Vxpipe.Gateway.Telephony.{MediaAdmission, OutgoingLegLifecycle}

  def new(%OutboundLegRequest{purpose: :initial, room_owner: owner}, service)
      when is_pid(owner) do
    %{
      room_monitor: Process.monitor(owner),
      answered?: false,
      cancel_pending?: false,
      detection: if(service.answering_machine_detection == :detect, do: :pending, else: :complete)
    }
  end

  def new(_transfer, _service), do: nil

  def observe(%{initial: nil} = state, _event), do: state

  def observe(%{initial: %{answered?: false}} = state, %Event{kind: :answered}) do
    report(state, if(state.initial.detection == :pending, do: :connected, else: :answered))
    %{state | initial: %{state.initial | answered?: true}}
  end

  def observe(
        %{initial: %{detection: :pending}} = state,
        %Event{kind: :answering_machine, answering_machine: result}
      )
      when result in [:human, :unknown] do
    report(state, :answered)
    %{state | initial: %{state.initial | answered?: true, detection: :complete}}
  end

  def observe(state, %Event{kind: :ended, end_reason: reason}) do
    report(state, {:ended, reason})
    state
  end

  def observe(
        %{service: %{answering_machine_detection: :detect}} = state,
        %Event{kind: :answering_machine, answering_machine: :machine}
      ) do
    report(state, {:ended, :machine})
    state
  end

  def observe(state, _event), do: state

  def hold_media?(%{initial: %{detection: :pending}}), do: true
  def hold_media?(_state), do: false

  def cancellation_reason(%{initial: nil}), do: :transfer_cancelled
  def cancellation_reason(_initial), do: :call_cancelled

  def cancel(%{status: status, initial: %{cancel_pending?: false}} = state)
      when status in [:starting, :unknown] do
    Process.send_after(self(), :retire_unknown, state.service.media_token_ttl_ms)
    {:keep, %{state | initial: %{state.initial | cancel_pending?: true}}}
  end

  def cancel(%{status: status, initial: initial} = state)
      when status in [:starting, :unknown] and initial != nil, do: {:keep, state}

  def cancel(%{binding: nil} = state), do: {:stop, state}

  def cancel(state) do
    OutgoingLegLifecycle.end_attempt(state.binding, state.service, state.leg_id, :call_cancelled)
    {:stop, state}
  end

  def adopted(%{initial: %{cancel_pending?: true}} = state, %Event{kind: kind}) do
    if kind != :ended do
      OutgoingLegLifecycle.end_attempt(
        state.binding,
        state.service,
        state.leg_id,
        :call_cancelled
      )
    end

    {:stop, state}
  end

  def adopted(state, _event), do: {:keep, state}

  def retire(state) do
    MediaAdmission.revoke(state.media_admission, self())
    state
  end

  defp report(state, event) do
    send(
      state.request.room_owner,
      {:vxpipe_outbound_leg, state.request.attempt_id, self(), event}
    )
  end
end
