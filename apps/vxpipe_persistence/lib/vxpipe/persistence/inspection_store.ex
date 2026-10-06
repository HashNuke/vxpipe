defmodule Vxpipe.Persistence.InspectionStore do
  @moduledoc "Ecto adapter for bounded, tenant-scoped call inspection reads."

  @behaviour Vxpipe.Calls.InspectionRepository

  import Ecto.Query

  alias Vxpipe.Calls.{ArchiveStatus, CallListCursor, CallSummary, HistoryCursor}
  alias Vxpipe.Persistence.ArchiveRecordCodec
  alias Vxpipe.Persistence.Schema.{Call, CallSpec, CallSpecRevision, Tenant}
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
  alias Vxpipe.Persistence.Schema.VariableSnapshot, as: StoredSnapshot

  @impl true
  def list_calls(repo, tenant_key, limit, cursor) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        join: revision in CallSpecRevision,
        on: revision.id == call.call_spec_revision_id,
        join: call_spec in CallSpec,
        on: call_spec.id == revision.call_spec_id,
        left_join: latest_snapshot in StoredSnapshot,
        on: latest_snapshot.id == call.latest_variables_snapshot_id,
        where: tenant.key == ^tenant_key,
        order_by: [desc: call.created_at, desc: call.public_id],
        limit: ^limit,
        select: {call, call_spec.public_id, revision.revision, latest_snapshot.global_revision}
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
        join: revision in CallSpecRevision,
        on: revision.id == call.call_spec_revision_id,
        join: call_spec in CallSpec,
        on: call_spec.id == revision.call_spec_id,
        left_join: latest_snapshot in StoredSnapshot,
        on: latest_snapshot.id == call.latest_variables_snapshot_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: {call, call_spec.public_id, revision.revision, latest_snapshot.global_revision}
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

  @impl true
  def fetch_archive_status(repo, tenant_key, call_id) do
    with {:ok, call_key} <- fetch_call_key(repo, tenant_key, call_id),
         %{last_sequence: last_sequence, present_sequence_count: present_sequence_count} <-
           archive_sequence_metadata(repo, call_key),
         {:ok, missing_sequences} <- missing_sequences(repo, call_key, last_sequence),
         {:ok, closure} <- latest_closure(repo, call_key, tenant_key, call_id) do
      {:ok,
       ArchiveStatus.from_metadata(
         last_sequence,
         present_sequence_count,
         missing_sequences,
         closure
       )}
    end
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, %CallListCursor{} = cursor) do
    from([call, _tenant, _revision, _call_spec, _latest_snapshot] in query,
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

  defp archive_sequence_metadata(repo, call_key) do
    repo.one(
      from(fact in StoredFact,
        where: fact.call_id == ^call_key,
        select: %{
          last_sequence: max(fact.sequence),
          present_sequence_count: count(fact.sequence, :distinct)
        }
      )
    )
  end

  defp missing_sequences(_repo, _call_key, nil), do: {:ok, []}

  defp missing_sequences(repo, call_key, last_sequence) do
    statement = """
    SELECT candidate.sequence
    FROM generate_series(1, $2) AS candidate(sequence)
    LEFT JOIN call_facts AS fact
      ON fact.call_id = $1 AND fact.sequence = candidate.sequence
    WHERE fact.id IS NULL
    ORDER BY candidate.sequence
    LIMIT 100
    """

    case Ecto.Adapters.SQL.query(repo, statement, [call_key, last_sequence]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp latest_closure(repo, call_key, tenant_key, call_id) do
    query =
      from(fact in StoredFact,
        where: fact.call_id == ^call_key and fact.kind == "archive_stream_closed",
        order_by: [desc: fact.sequence, desc: fact.id],
        limit: 1
      )

    case repo.one(query) do
      nil -> {:ok, nil}
      stored -> ArchiveRecordCodec.call_fact(stored, tenant_key, call_id)
    end
  end

  defp to_summary(
         {call, call_spec_id, call_spec_revision, latest_variable_revision},
         tenant_key
       ) do
    %CallSummary{
      id: call.public_id,
      tenant_key: tenant_key,
      call_spec_id: call_spec_id,
      call_spec_revision: call_spec_revision,
      state: call.state,
      created_at: call.created_at,
      started_at: call.started_at,
      ended_at: call.ended_at,
      terminal_reason: call.terminal_reason,
      outgoing_outcome: call.outgoing_outcome,
      dial_submitted_at: call.dial_submitted_at,
      answered_at: call.answered_at,
      dial_ended_at: call.dial_ended_at,
      latest_variable_revision: latest_variable_revision
    }
  end
end
