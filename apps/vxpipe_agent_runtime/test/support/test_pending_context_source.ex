defmodule Vxpipe.AgentRuntime.TestPendingContextSource do
  @behaviour Vxpipe.AgentRuntime.PendingContextSource

  @impl true
  def snapshot(config, correlation, timeout_ms) do
    send(config.owner, {:pending_context_requested, self(), correlation, timeout_ms})

    case config.result do
      :block -> await_release()
      result -> result
    end
  end

  defp await_release do
    receive do
      {:release, result} -> result
    end
  end
end
