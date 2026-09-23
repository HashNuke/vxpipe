defmodule Vxpipe.CallEngine.Speech.EventDelivery do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{
    Allocation,
    Event,
    EventQueue,
    OutputState,
    ResponseContexts,
    ResponseStarts,
    STSOutput
  }

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
    if staged_context_input?(state) and not accepted_prior_origin?(event, state) do
      %{state | input: Map.put(state.input, :unsafe_events?, true)}
    else
      state
    end
  end

  def accept_response_start(%Event{response_context: context} = event, state) do
    case ResponseContexts.status(state.response_contexts, context) do
      :accepted ->
        record_response_start(event, state)

      :staged ->
        pending = state.response_contexts.pending

        case state.input do
          %{command: %{ref: reference, response_context: ^context}}
          when pending == {reference, context} ->
            record_response_start(event, state)

          _other ->
            {:error, :stale_response}
        end

      :unknown ->
        {:error, :stale_response}
    end
  end

  def accept_tool_call(%Event{response_context: context} = event, state) do
    case ResponseContexts.status(state.response_contexts, context) do
      :accepted ->
        {:ok, event, state}

      :staged ->
        case {state.response_contexts.pending, state.input} do
          {{reference, ^context}, %{command: %{ref: reference, response_context: ^context}}} ->
            {:ok, event, state}

          _other ->
            {:error, :stale_response}
        end

      :unknown ->
        if is_reference(context),
          do: {:error, :stale_response},
          else: {:error, :invalid_event}
    end
  end

  def acknowledge(%Event{kind: :response_started} = event, state) do
    case ResponseStarts.acknowledge(state.response_starts, event) do
      {:ok, starts} -> {:ok, %{state | response_starts: starts}}
      error -> error
    end
  end

  def acknowledge(%Event{kind: :ready}, state), do: {:ok, %{state | ready_acked?: true}}

  def acknowledge(%Event{kind: :output_completed, request_ref: reference}, state),
    do: {:ok, STSOutput.acknowledge(state, reference)}

  def acknowledge(
        %Event{kind: :input_submitted, request_ref: reference},
        %{output: %OutputState{request: %{ref: reference}}} = state
      ),
      do: {:ok, %{state | output: OutputState.mark_submission_acked(state.output, reference)}}

  def acknowledge(_event, state), do: {:ok, state}

  defp record_response_start(event, state) do
    case ResponseStarts.accept(state.response_starts, event) do
      {:ok, starts} -> {:ok, event, %{state | response_starts: starts}}
      error -> error
    end
  end

  defp accepted_prior_origin?(
         %Event{kind: kind, response_context: context},
         state
       )
       when kind in [:response_started, :tool_call] do
    context != state.input.command.response_context and
      ResponseContexts.status(state.response_contexts, context) == :accepted
  end

  defp accepted_prior_origin?(_event, _state), do: false
end
