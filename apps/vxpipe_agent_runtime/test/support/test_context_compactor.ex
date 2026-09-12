defmodule Vxpipe.AgentRuntime.TestContextCompactor do
  @behaviour Vxpipe.AgentRuntime.ContextCompactor

  @impl true
  def compact(%{owner: owner, result: result}, request) do
    send(owner, {:context_compaction_requested, self(), request})

    case result do
      :manual ->
        receive do
          {:context_compaction_result, response} -> response
        end

      fixed ->
        fixed
    end
  end
end
