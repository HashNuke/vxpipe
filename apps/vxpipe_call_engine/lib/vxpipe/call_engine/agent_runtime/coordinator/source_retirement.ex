defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.SourceRetirement do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{
    ActiveRequest,
    HeldOutput,
    OutputSettlement,
    RequestOutcome,
    State
  }

  def cancel(%State{current: nil} = state, _retired?, _timeout), do: {:ok, state}

  def cancel(%State{current: current} = state, retired?, timeout) do
    if retired?.(current.command) do
      :ok = ActiveRequest.cancel(current, state.session, timeout)
      retire_cancelled(state, current)
    else
      {:ok, state}
    end
  end

  defp retire_cancelled(
         %State{held_output: %HeldOutput{}} = state,
         %ActiveRequest{kind: {:completion, continuation}} = current
       ) do
    with :ok <-
           CompletionContinuation.retain(continuation, state.session, state.invocation_registry),
         receipt when receipt in [:ok, {:error, :stale_settlement}] <-
           Session.settle_output(state.session, current.correlation, nil) do
      {:ok, %{state | held_output: nil, current: nil}}
    else
      _ -> {:stop, :completion_retirement_failed, state}
    end
  end

  defp retire_cancelled(state, current) do
    case RequestOutcome.fail_uncommitted(
           current,
           :interrupted,
           State.request_outcome_options(state)
         ) do
      :advance -> {:ok, %{OutputSettlement.await(state) | current: nil}}
      {:stop, reason} -> {:stop, reason, state}
    end
  end

  def settle(%State{awaiting_output: nil} = state, _retired?, _visible, _finish),
    do: {:ok, state}

  def settle(%State{awaiting_output: pending} = state, retired?, visible, finish) do
    if retired?.(pending.command) and pending.command.id not in visible do
      case OutputSettlement.settle(state, pending.command, nil) do
        {:ok, state} ->
          case HeldOutput.release(state, pending.command, finish) do
            {:stop, _, _} = stop -> stop
            released -> {:ok, released}
          end

        _ ->
          {:stop, :output_retirement_failed, state}
      end
    else
      {:ok, state}
    end
  end
end
