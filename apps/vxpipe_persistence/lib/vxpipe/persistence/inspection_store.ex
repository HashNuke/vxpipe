defmodule Vxpipe.Persistence.InspectionStore do
  @moduledoc "Ecto adapter for bounded, tenant-scoped call inspection reads."

  @behaviour Vxpipe.Calls.InspectionRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallListCursor, CallSummary, HistoryCursor}
  alias Vxpipe.Persistence.ArchiveRecordCodec
  alias Vxpipe.Persistence.Schema.{Call, CallDefinition, DefinitionRevision, Tenant}
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
  alias Vxpipe.Persistence.Schema.VariableSnapshot, as: StoredSnapshot

  @impl true
  def list_calls(repo, tenant_key, limit, cursor) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: call.created_at, desc: call.public_id],
        limit: ^limit,
        select: {call, definition.public_id, revision.revision}
      )

    calls =
      query
      |> after_cursor(cursor)
      |> repo.all()
      |> Enum.map(&to_summary(&1, tenant_key))

    {:ok, calls}
  end

  @impl true
  def fetch_call(repo, tenant_key, call_id) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: {call, definition.public_id, revision.revision}
      )

    case repo.one(query) do
      nil -> {:error, :call_not_found}
      stored -> {:ok, to_summary(stored, tenant_key)}
    end
  end

  @impl true
  def list_history_records(repo, tenant_key, call_id, limit, cursor) do
    with {:ok, call_key} <- fetch_call_key(repo, tenant_key, call_id),
         {:ok, facts} <- fetch_facts(repo, call_key, tenant_key, call_id, limit, cursor),
         {:ok, snapshots} <-
           fetch_snapshots(repo, call_key, tenant_key, call_id, limit, cursor) do
      records =
        (facts ++ snapshots)
        |> Enum.sort_by(&HistoryCursor.record_key/1, :desc)
        |> Enum.take(limit)

      {:ok, records}
    end
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, %CallListCursor{} = cursor) do
    from([call, _tenant, _revision, _definition] in query,
      where:
        call.created_at < ^cursor.created_at or
          (call.created_at == ^cursor.created_at and call.public_id < ^cursor.call_id)
    )
  end

  defp fetch_call_key(repo, tenant_key, call_id) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call.id
      )

    case repo.one(query) do
      nil -> {:error, :call_not_found}
      call_key -> {:ok, call_key}
    end
  end

  defp fetch_facts(repo, call_key, tenant_key, call_id, limit, cursor) do
    stored =
      StoredFact
      |> where([fact], fact.call_id == ^call_key)
      |> fact_after_cursor(cursor)
      |> order_by([fact], desc: fact.occurred_at, desc: fact.sequence, desc: fact.public_id)
      |> limit(^limit)
      |> repo.all()

    ArchiveRecordCodec.call_facts(stored, tenant_key, call_id)
  end

  defp fetch_snapshots(repo, call_key, tenant_key, call_id, limit, cursor) do
    stored =
      StoredSnapshot
      |> where([snapshot], snapshot.call_id == ^call_key)
      |> snapshot_after_cursor(cursor)
      |> order_by(
        [snapshot],
        desc: snapshot.occurred_at,
        desc: snapshot.global_revision,
        desc: snapshot.public_id
      )
      |> limit(^limit)
      |> repo.all()

    ArchiveRecordCodec.variable_snapshots(stored, tenant_key, call_id)
  end

  defp fact_after_cursor(query, nil), do: query

  defp fact_after_cursor(query, %HistoryCursor{source: :variable_snapshot} = cursor) do
    from(fact in query,
      where: fact.occurred_at < ^cursor.occurred_at or fact.occurred_at == ^cursor.occurred_at
    )
  end

  defp fact_after_cursor(query, %HistoryCursor{source: :fact} = cursor) do
    from(fact in query,
      where:
        fact.occurred_at < ^cursor.occurred_at or
          (fact.occurred_at == ^cursor.occurred_at and fact.sequence < ^cursor.position) or
          (fact.occurred_at == ^cursor.occurred_at and fact.sequence == ^cursor.position and
             fact.public_id < ^cursor.record_id)
    )
  end

  defp snapshot_after_cursor(query, nil), do: query

  defp snapshot_after_cursor(query, %HistoryCursor{source: :fact} = cursor) do
    from(snapshot in query, where: snapshot.occurred_at < ^cursor.occurred_at)
  end

  defp snapshot_after_cursor(query, %HistoryCursor{source: :variable_snapshot} = cursor) do
    from(snapshot in query,
      where:
        snapshot.occurred_at < ^cursor.occurred_at or
          (snapshot.occurred_at == ^cursor.occurred_at and
             snapshot.global_revision < ^cursor.position) or
          (snapshot.occurred_at == ^cursor.occurred_at and
             snapshot.global_revision == ^cursor.position and
             snapshot.public_id < ^cursor.record_id)
    )
  end

  defp to_summary({call, definition_id, definition_revision}, tenant_key) do
    %CallSummary{
      id: call.public_id,
      tenant_key: tenant_key,
      definition_id: definition_id,
      definition_revision: definition_revision,
      state: call.state,
      created_at: call.created_at,
      started_at: call.started_at,
      ended_at: call.ended_at,
      terminal_reason: call.terminal_reason
    }
  end
end
