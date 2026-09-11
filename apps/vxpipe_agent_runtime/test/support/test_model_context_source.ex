defmodule Vxpipe.AgentRuntime.TestModelContextSource do
  @behaviour Vxpipe.AgentRuntime.ModelContextSource

  @impl true
  def snapshot(owner, correlation, timeout_ms) do
    send(owner, {:model_context_requested, self(), correlation, timeout_ms})

    receive do
      {:model_context_result, result} -> result
    end
  end
end
