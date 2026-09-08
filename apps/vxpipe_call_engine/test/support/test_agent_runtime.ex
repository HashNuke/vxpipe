defmodule Vxpipe.CallEngine.TestAgentRuntime do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.AgentRuntime

  @impl true
  def ask(observer, query, options) when is_pid(observer) do
    request_id = Keyword.fetch!(options, :request_id)
    send(observer, {:test_agent_request, self(), request_id, query, options})
    {:ok, request_id}
  end

  @impl true
  def cancel(observer, request_id, reason) when is_pid(observer) do
    send(observer, {:test_agent_cancel, self(), request_id, reason})
    :ok
  end

  @impl true
  def discard_requests(observer, request_ids) when is_pid(observer) do
    send(observer, {:test_agent_discard, self(), request_ids})
    :ok
  end
end
