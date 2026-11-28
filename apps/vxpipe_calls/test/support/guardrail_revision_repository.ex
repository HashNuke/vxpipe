defmodule Vxpipe.Calls.TestGuardrailRevisionRepository do
  @moduledoc false
  alias Vxpipe.Calls.TestMemoryRepository

  def allocate_id(%{agent: agent}), do: TestMemoryRepository.allocate_id(agent)

  def next_revision(%{agent: agent}, tenant, id),
    do: TestMemoryRepository.next_revision(agent, tenant, id)

  def fetch_published_revision(%{agent: agent}, tenant, id),
    do: TestMemoryRepository.fetch_published_revision(agent, tenant, id)

  def fetch_revision(state, tenant, id, revision) do
    snapshot = TestMemoryRepository.fetch_revision(state.agent, tenant, id, revision)
    if callback = state[:after_read], do: callback.()
    snapshot
  end

  def insert_revision(state, tenant, revision, routes) do
    if state[:conflict?] && state.conflict?.() do
      {:error, :revision_conflict}
    else
      TestMemoryRepository.insert_revision(state.agent, tenant, revision, routes)
    end
  end
end
