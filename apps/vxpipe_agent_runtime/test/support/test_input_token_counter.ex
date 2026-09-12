defmodule Vxpipe.AgentRuntime.TestInputTokenCounter do
  @behaviour Vxpipe.AgentRuntime.InputTokenCounter

  @impl true
  def count(%{owner: owner, result: result}, request) do
    send(owner, {:input_tokens_counted, self(), request})
    result
  end
end
