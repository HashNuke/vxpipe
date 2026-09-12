defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.CompactionUsage do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{ActiveRequest, State}
  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation
  alias Vxpipe.CallEngine.Usage.ModelProjection
  alias Vxpipe.CallEngine.Id

  @spec record(State.t(), map(), map()) :: State.t()
  def record(%State{} = state, correlation, data)
      when is_map(correlation) and is_map(data) do
    case ModelProjection.project(data, correlation, state.usage_provider,
           call_id: state.call_id,
           activation_id: state.activation_id,
           attempt_id: Id.generate(:model_attempt),
           tool_call_id: tool_call_id(state.current),
           outcome: Map.get(data, :outcome),
           purpose: :context_compaction
         ) do
      {:ok, observations} ->
        send(state.owner, {:vxpipe_usage_observations, self(), observations})

      {:error, :invalid_model_usage} ->
        :ok
    end

    state
  end

  defp tool_call_id(%ActiveRequest{
         kind: {:completion, %CompletionContinuation{} = continuation}
       }),
       do: continuation.invocation_id

  defp tool_call_id(%ActiveRequest{}), do: nil
end
