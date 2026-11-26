defmodule Vxpipe.AgentRuntime.TestPreflightExecutor do
  @behaviour Vxpipe.AgentRuntime.Executor

  @impl true
  def preflight(%{identity: :block, test_owner: owner}, _, _, _) do
    send(owner, :preflight_entered)

    receive do
      :release_preflight -> :ok
    end
  end

  def preflight(%{identity: reason}, _, _, _), do: {:error, reason}

  @impl true
  def submit(%{test_owner: owner}, _, _, _) do
    send(owner, :submit_called)
    {:accepted, :non_blocking}
  end
end
