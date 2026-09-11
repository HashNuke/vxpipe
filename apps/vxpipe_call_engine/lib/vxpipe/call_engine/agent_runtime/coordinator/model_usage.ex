defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.ModelUsage do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{State, UsageRounds}
  alias Vxpipe.CallEngine.Usage.ModelProjection

  @spec record(State.t(), map(), map()) :: State.t()
  def record(%State{} = state, correlation, data)
      when is_map(correlation) and is_map(data) do
    case UsageRounds.next(state.usage_rounds, correlation) do
      {:ok, round, usage_rounds} ->
        state = %{state | usage_rounds: usage_rounds}
        emit(data, correlation, round, state)
        state

      {:error, :unknown_request} ->
        state
    end
  end

  @spec complete(State.t(), map()) :: State.t()
  def complete(%State{} = state, correlation) when is_map(correlation) do
    %{state | usage_rounds: UsageRounds.complete(state.usage_rounds, correlation)}
  end

  defp emit(data, correlation, round, state) do
    case ModelProjection.project(data, correlation, state.usage_provider,
           call_id: state.call_id,
           activation_id: state.activation_id,
           attempt_id: round.attempt_id,
           tool_call_id: round.tool_call_id
         ) do
      {:ok, observations} ->
        send(state.owner, {:vxpipe_usage_observations, self(), observations})

      {:error, :invalid_model_usage} ->
        :ok
    end
  end
end
