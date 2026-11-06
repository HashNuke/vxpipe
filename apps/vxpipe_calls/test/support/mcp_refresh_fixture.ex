defmodule Vxpipe.Calls.Test.MCPRefreshFixture do
  def run(_context, _tenant, operation), do: operation.()

  def claim({owner, _result}, tenant, id, generation, revision) do
    send(owner, {:claimed, tenant, id, generation, revision})
    {:ok, %Vxpipe.Calls.ResolvedMCPRefresh{id: "claim", grant_revision: revision, secrets: %{}}}
  end

  def refresh({owner, result}, _claim) do
    send(owner, :refreshed)
    result
  end

  def complete({owner, _}, tenant, id, generation, claim, tokens) do
    send(owner, {:committed, tenant, id, generation, claim, tokens})
    :ok
  end

  def fail({owner, _}, tenant, id, generation, claim) do
    send(owner, {:failed, tenant, id, generation, claim})
    :ok
  end
end
