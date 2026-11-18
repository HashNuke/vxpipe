defmodule Vxpipe.AgentRuntime.RepairModelProvider do
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  @impl true
  defdelegate supports_protocol?(model, protocol, tools),
    to: Vxpipe.AgentRuntime.TestStreamingModelProvider

  @impl true
  defdelegate generate(model, request), to: Vxpipe.AgentRuntime.TestStreamingModelProvider

  @impl true
  defdelegate stream(model, request, emit), to: Vxpipe.AgentRuntime.TestStreamingModelProvider

  @impl true
  def maximum_output_tokens(model), do: limit(model, :output_limit)

  @impl true
  def context_window_tokens(model), do: limit(model, :context_window)

  defp limit(model, key) do
    case Map.get(model, :limits_source) do
      nil -> Map.get(model, key)
      source -> Agent.get(source, &Map.get(&1, key))
    end
  end
end
