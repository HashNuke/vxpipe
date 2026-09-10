defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.Interruption do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{ActiveRequest, History, State}
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Telemetry

  @spec apply(State.t(), [History.identity()], timeout()) ::
          {:ok, [SendText.t()], State.t()} | {:error, :unavailable, State.t()}
  def apply(%State{} = state, completed_turn_ids, timeout) when is_list(completed_turn_ids) do
    current = state.current
    interrupted = interrupted_commands(state)
    report_interruption(current, state)
    state = cancel_current(state, timeout)
    {correlations, history} = History.select(state.history, completed_turn_ids)
    state = %{state | history: history, pending: :queue.new()}
    correlations = current_correlations(current) ++ correlations

    with {:ok, state} <- settle_completion(current, state, timeout),
         :ok <- discard(state.session, Enum.uniq(correlations), timeout) do
      {:ok, interrupted, state}
    else
      {:error, :unavailable} -> {:error, :unavailable, state}
    end
  end

  defp interrupted_commands(state) do
    pending = :queue.to_list(state.pending)

    case state.current do
      %ActiveRequest{kind: :caller, command: %SendText{} = command} -> [command | pending]
      %ActiveRequest{kind: {:completion, _continuation}} -> pending
      nil -> pending
    end
  end

  defp report_interruption(
         %ActiveRequest{kind: :caller, command: %SendText{} = command} = current,
         state
       ) do
    send(state.owner, {:vxpipe_capability_failed, self(), command, :interrupted})

    Telemetry.model_request_stop(
      current.started_at,
      state.provider,
      :interrupted,
      current.first_output_observed?
    )
  end

  defp report_interruption(_current, _state), do: :ok

  defp cancel_current(%State{current: nil} = state, _timeout), do: state

  defp cancel_current(%State{current: %ActiveRequest{} = current} = state, timeout) do
    :ok = ActiveRequest.cancel(current, state.session, timeout)
    %{state | current: nil}
  end

  defp settle_completion(nil, state, _timeout), do: {:ok, state}
  defp settle_completion(%ActiveRequest{kind: :caller}, state, _timeout), do: {:ok, state}

  defp settle_completion(
         %ActiveRequest{kind: {:completion, continuation}, correlation: correlation},
         state,
         timeout
       ) do
    with {:ok, durable?} <- durable?(state.session, correlation, timeout),
         :ok <- settle_lease(continuation, durable?, state.invocation_registry) do
      {:ok, %{state | completion_deferred?: not durable?}}
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  defp settle_lease(continuation, true, registry) do
    CompletionContinuation.acknowledge(registry, continuation)
  end

  defp settle_lease(continuation, false, registry) do
    CompletionContinuation.release(registry, continuation)
  end

  defp durable?(session, correlation, timeout) do
    case Session.durable?(session, correlation, timeout) do
      {:ok, durable?} when is_boolean(durable?) -> {:ok, durable?}
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp current_correlations(nil), do: []
  defp current_correlations(%ActiveRequest{correlation: correlation}), do: [correlation]

  defp discard(session, correlations, timeout) do
    case Session.discard(session, correlations, timeout) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
