defmodule Vxpipe.Calls.TestArchiveRepository do
  use Agent

  @behaviour Vxpipe.Calls.ArchiveRepository

  alias Vxpipe.Calls.VariableSnapshotHistory

  def start_link(_options), do: Agent.start_link(fn -> %{operations: [], snapshots: []} end)

  def repository(agent), do: {__MODULE__, agent}
  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  @impl true
  def store_variable_snapshot(agent, snapshot) do
    Agent.update(agent, fn state ->
      %{
        state
        | operations: [{:store, snapshot.id} | state.operations],
          snapshots: [snapshot | state.snapshots]
      }
    end)

    {:ok, snapshot}
  end

  @impl true
  def fetch_variable_snapshots(agent, tenant_key, call_id) do
    Agent.get_and_update(agent, fn state ->
      snapshots =
        state.snapshots
        |> Enum.filter(&(&1.tenant_key == tenant_key and &1.call_id == call_id))
        |> Enum.sort_by(& &1.global_revision)

      latest = List.last(snapshots)
      result = {:ok, %VariableSnapshotHistory{snapshots: snapshots, latest: latest}}

      {result, %{state | operations: [{:fetch, tenant_key, call_id} | state.operations]}}
    end)
  end
end
