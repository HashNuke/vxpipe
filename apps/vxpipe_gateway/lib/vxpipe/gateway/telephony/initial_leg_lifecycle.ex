defmodule Vxpipe.Gateway.Telephony.InitialLegLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}

  def new(%OutboundLegRequest{purpose: :initial, room_owner: owner}, service)
      when is_pid(owner) do
    %{
      room_monitor: Process.monitor(owner),
      answered?: false,
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

  defp report(state, event) do
    send(
      state.request.room_owner,
      {:vxpipe_outbound_leg, state.request.attempt_id, self(), event}
    )
  end
end
