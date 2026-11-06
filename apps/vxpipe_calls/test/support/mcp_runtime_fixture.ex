defmodule Vxpipe.Calls.Test.MCPRuntimeFixture do
  def run(_context, _tenant, operation), do: operation.()

  def resolve({owner, agent}, _tenant, _id) do
    send(owner, :resolved)
    {:ok, Agent.get(agent, & &1)}
  end

  def claim({_owner, agent}, _tenant, _id, _generation, revision),
    do:
      {:ok,
       %Vxpipe.Calls.ResolvedMCPRefresh{
         id: "claim",
         grant_revision: revision,
         secrets: Agent.get(agent, & &1.secrets)
       }}

  def refresh({owner, _agent}, _claim) do
    send(owner, :refreshed)
    {:ok, %{"access_token" => "new", "expires_at" => "2026-11-06T12:10:00Z"}}
  end

  def complete({_owner, agent}, _, _, _, _, tokens) do
    Agent.update(agent, fn saved -> %{saved | secrets: Map.merge(saved.secrets, tokens)} end)
    :ok
  end

  def fail(_, _, _, _, _), do: :ok

  def refresh_catalog({owner, agent}, tenant, id, generation, attributes) do
    send(owner, {:catalog_refreshed, attributes})

    Agent.get_and_update(agent, fn saved ->
      if saved.connection.generation == generation and saved.connection.id == id and
           saved.connection.tenant_key == tenant do
        changed = %{saved | connection: Map.merge(saved.connection, attributes)}
        {{:ok, changed.connection}, changed}
      else
        {{:error, :stale_mcp_connection}, saved}
      end
    end)
  end
end
