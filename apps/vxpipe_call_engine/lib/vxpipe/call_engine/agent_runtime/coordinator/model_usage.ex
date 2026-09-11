defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.ModelUsage do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{State, UsageRounds}
  alias Vxpipe.CallEngine.Usage.ModelProjection

  @spec start(State.t(), map()) :: State.t()
  def start(%State{} = state, correlation) when is_map(correlation) do
    case UsageRounds.start(state.usage_rounds, correlation) do
      {:ok, usage_rounds} -> %{state | usage_rounds: usage_rounds}
      {:error, _reason} -> state
    end
  end

  @spec record(State.t(), map(), map()) :: State.t()
  def record(%State{} = state, correlation, data)
      when is_map(correlation) and is_map(data) do
    case UsageRounds.finish(state.usage_rounds, correlation) do
      {:ok, round, usage_rounds} ->
        state = %{state | usage_rounds: usage_rounds}
        emit(data, correlation, round, state)
        state

      {:error, :unknown_attempt} ->
        state
    end
  end

  @spec complete(State.t(), map(), :succeeded | :failed | :cancelled) :: State.t()
  def complete(%State{} = state, correlation, outcome)
      when is_map(correlation) and outcome in [:succeeded, :failed, :cancelled] do
    case UsageRounds.complete(state.usage_rounds, correlation) do
      {nil, usage_rounds} ->
        %{state | usage_rounds: usage_rounds}

      {round, usage_rounds} ->
        state = %{state | usage_rounds: usage_rounds}
        emit(%{}, correlation, round, state, outcome)
        state
    end
  end

  defp emit(data, correlation, round, state, outcome \\ :succeeded) do
    case ModelProjection.project(data, correlation, state.usage_provider,
           call_id: state.call_id,
           activation_id: state.activation_id,
           attempt_id: round.attempt_id,
           tool_call_id: round.tool_call_id,
           outcome: outcome
         ) do
      {:ok, observations} ->
        send(state.owner, {:vxpipe_usage_observations, self(), observations})

      {:error, :invalid_model_usage} ->
        :ok
    end
  end
end
