defmodule Vxpipe.Persistence.TestRecoveringArchiveRepository do
  @moduledoc false

  use Agent

  @behaviour Vxpipe.Calls.ArchiveRepository

  alias Vxpipe.Calls.VariableSnapshotHistory

  def start_link(options) do
    mode = Keyword.get(options, :mode, :raise)
    observer = Keyword.fetch!(options, :observer)

    Agent.start_link(fn ->
      %{facts: [], mode: mode, observer: observer, snapshots: []}
    end)
  end

  def repository(server), do: {__MODULE__, server}
  def recover(server), do: Agent.update(server, &%{&1 | mode: :available})
  def facts(server), do: Agent.get(server, &Enum.reverse(&1.facts))

  @impl true
  def store_call_fact(server, fact) do
    store(server, :facts, fact)
  end

  @impl true
  def fetch_call_facts(server, tenant_key, call_id) do
    facts =
      server
      |> facts()
      |> Enum.filter(&(&1.tenant_key == tenant_key and &1.call_id == call_id))

    {:ok, facts}
  end

  @impl true
  def store_variable_snapshot(server, snapshot) do
    store(server, :snapshots, snapshot)
  end

  @impl true
  def fetch_variable_snapshots(server, tenant_key, call_id) do
    snapshots =
      Agent.get(server, fn state ->
        state.snapshots
        |> Enum.reverse()
        |> Enum.filter(&(&1.tenant_key == tenant_key and &1.call_id == call_id))
      end)

    {:ok, %VariableSnapshotHistory{snapshots: snapshots, latest: List.last(snapshots)}}
  end

  defp store(server, collection, value) do
    {mode, observer} = Agent.get(server, &{&1.mode, &1.observer})
    send(observer, {:test_archive_repository_attempt, value, mode})

    case mode do
      :available ->
        Agent.update(server, &Map.update!(&1, collection, fn values -> [value | values] end))
        send(observer, {:test_archive_repository_stored, value})
        {:ok, value}

      :raise ->
        raise "simulated archive repository crash"
    end
  end
end
