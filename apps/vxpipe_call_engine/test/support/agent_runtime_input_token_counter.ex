defmodule Vxpipe.CallEngine.TestAgentRuntimeInputTokenCounter do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.InputTokenCounter

  @impl true
  def count(owner, request) when is_pid(owner) do
    send(owner, {:test_agent_runtime_input_count, self(), request})

    receive do
      {:test_agent_runtime_input_tokens, count} -> {:ok, count}
      {:test_agent_runtime_input_error, reason} -> {:error, reason}
    end
  end
end
