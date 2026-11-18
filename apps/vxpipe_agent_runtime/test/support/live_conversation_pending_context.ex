defmodule Vxpipe.AgentRuntime.LiveConversationPendingContext do
  @moduledoc false
  @behaviour Vxpipe.AgentRuntime.PendingContextSource

  @impl true
  def snapshot(agent, _correlation, timeout_ms), do: {:ok, Agent.get(agent, & &1, timeout_ms)}
end
