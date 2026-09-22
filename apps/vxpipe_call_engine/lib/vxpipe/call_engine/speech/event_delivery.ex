defmodule Vxpipe.CallEngine.Speech.EventDelivery do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Allocation, Event, EventQueue, ResponseContexts}

  def dispatch(%{active?: true} = state) do
    if Allocation.valid?(state.allocation) do
      case if(staged_context_input?(state), do: :empty, else: EventQueue.take(state.events)) do
        {:ok, event, false, events} ->
          send(state.consumer, {:vxpipe_speech, event})
          %{state | events: events}

        {:ok, _event, true, events} ->
          %{state | events: events}

        :empty ->
          state
      end
    else
      state
    end
  end

  def dispatch(state), do: state

  def pre_deliver_terminal?(
        %EventQueue{
          awaiting: %Event{kind: :input_submitted, request_ref: reference}
        },
        %Event{kind: kind, request_ref: reference}
      )
      when kind in [:completed, :cancelled],
      do: true

  def pre_deliver_terminal?(_events, _event), do: false

  def staged_context_input?(%{
        descriptor: %{response_start?: true},
        input: %{command: %{response_context: context}}
      })
      when is_reference(context),
      do: true

  def staged_context_input?(_state), do: false

  def rejected_with_early_events?(state, input, result),
    do: result != :ok and staged_context_input?(state) and input.unsafe_events?

  def note_early_event(event, state) do
    if staged_context_input?(state) and not accepted_prior_response?(event, state) do
      %{state | input: Map.put(state.input, :unsafe_events?, true)}
    else
      state
    end
  end

  def accept_response_start(%Event{response_context: context} = event, state) do
    case ResponseContexts.status(state.response_contexts, context) do
      :accepted ->
        {:ok, event, state}

      :staged ->
        pending = state.response_contexts.pending

        case state.input do
          %{command: %{ref: reference, response_context: ^context}}
          when pending == {reference, context} ->
            {:ok, event, state}

          _other ->
            {:error, :stale_response}
        end

      :unknown ->
        {:error, :stale_response}
    end
  end

  defp accepted_prior_response?(
         %Event{kind: :response_started, response_context: context},
         state
       ) do
    context != state.input.command.response_context and
      ResponseContexts.status(state.response_contexts, context) == :accepted
  end

  defp accepted_prior_response?(_event, _state), do: false
end
