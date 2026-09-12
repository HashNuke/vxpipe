defmodule Vxpipe.Persistence.CallDetailsInspectionStore do
  @moduledoc "Ecto read adapter for safe tenant-scoped call-details revisions and documents."

  @behaviour Vxpipe.Calls.CallDetailsInspectionRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallDetailsCursor, CallDetailsDocument, CallDetailsRevision}
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.CallDetailsPublication, as: StoredPublication

  @impl true
  def list(repo, tenant_key, call_id, limit, cursor)
      when is_integer(limit) and limit > 0 do
    revisions =
      StoredPublication
      |> join(:inner, [publication], call in Call, on: call.id == publication.call_id)
      |> join(:inner, [_publication, call], tenant in Tenant, on: tenant.id == call.tenant_id)
      |> where(
        [_publication, call, tenant],
        tenant.key == ^tenant_key and call.public_id == ^call_id
      )
      |> after_cursor(cursor)
      |> order_by([publication], desc: publication.recorded_at, desc: publication.public_id)
      |> limit(^limit)
      |> select([publication, call], {publication, call.latest_details_publication_id})
      |> repo.all()
      |> Enum.map(&revision/1)

    {:ok, revisions}
  end

  @impl true
  def fetch(repo, tenant_key, call_id, publication_id) do
    query =
      from(publication in StoredPublication,
        join: call in Call,
        on: call.id == publication.call_id,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where:
          tenant.key == ^tenant_key and call.public_id == ^call_id and
            publication.public_id == ^publication_id and publication.status == :published,
        select: publication
      )

    case repo.one(query) do
      nil -> {:error, :call_details_not_found}
      stored -> {:ok, document(stored)}
    end
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, %CallDetailsCursor{} = cursor) do
    from([publication, _call, _tenant] in query,
      where:
        publication.recorded_at < ^cursor.recorded_at or
          (publication.recorded_at == ^cursor.recorded_at and
             publication.public_id < ^cursor.publication_id)
    )
  end

  defp revision({stored, latest_id}) do
    %CallDetailsRevision{
      id: stored.public_id,
      recorded_at: stored.recorded_at,
      filename: stored.filename,
      completeness: stored.completeness,
      status: stored.status,
      checksum: checksum(stored.checksum),
      size_bytes: byte_size(stored.contents),
      published_at: stored.published_at,
      latest?: stored.id == latest_id
    }
  end

  defp document(stored) do
    %CallDetailsDocument{
      id: stored.public_id,
      recorded_at: stored.recorded_at,
      filename: stored.filename,
      completeness: stored.completeness,
      checksum: checksum(stored.checksum),
      contents: stored.contents,
      published_at: stored.published_at
    }
  end

  defp checksum(digest), do: "sha256:" <> Base.encode16(digest, case: :lower)
end
