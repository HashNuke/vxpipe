defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.Interruption do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{ActiveRequest, History, State}
  alias Vxpipe.CallEngine.Command.SendText

  @spec apply(State.t(), [History.identity()], timeout()) ::
          {:ok, [SendText.t()], State.t()} | {:error, :unavailable, State.t()}
  def apply(
        %State{current: %ActiveRequest{kind: {:completion, _continuation}}} = state,
        _ids,
        _timeout
      ) do
    {:error, :unavailable, state}
  end

  def apply(%State{} = state, completed_turn_ids, timeout) when is_list(completed_turn_ids) do
    interrupted = interrupted_commands(state)
    state = cancel_current(state, timeout)
    {correlations, history} = History.select(state.history, completed_turn_ids)
    state = %{state | history: history, pending: :queue.new()}

    case discard(state.session, correlations, timeout) do
      :ok -> {:ok, interrupted, state}
      {:error, :unavailable} -> {:error, :unavailable, state}
    end
  end

  defp interrupted_commands(state) do
    pending = :queue.to_list(state.pending)

    case state.current do
      %ActiveRequest{kind: :caller, command: %SendText{} = command} -> [command | pending]
      nil -> pending
    end
  end

  defp cancel_current(%State{current: nil} = state, _timeout), do: state

  defp cancel_current(%State{current: %ActiveRequest{} = current} = state, timeout) do
    :ok = ActiveRequest.cancel(current, state.session, timeout)
    %{state | current: nil}
  end

  defp discard(session, correlations, timeout) do
    case Session.discard(session, correlations, timeout) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
