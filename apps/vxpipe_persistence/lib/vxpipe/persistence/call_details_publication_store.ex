defmodule Vxpipe.Persistence.CallDetailsPublicationStore do
  @moduledoc "Ecto adapter for immutable call-details revisions and their latest pointer."

  @behaviour Vxpipe.Calls.PublicationRepository

  import Ecto.Query

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication, CallDetailsSnapshot}
  alias Vxpipe.Persistence.{
    CallDetailsPublicationHead,
    CallDetailsPublicationPending,
    CallDetailsPublicationRecord
  }
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.CallDetailsPublication, as: StoredPublication

  @impl true
  def reserve(repo, tenant_key, call_id, %CallDetailsSnapshot{} = snapshot) do
    case repo.transaction(fn -> reserve_transaction(repo, tenant_key, call_id, snapshot) end) do
      {:ok, {publication, disposition}} -> {:ok, publication, disposition}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def mark_published(
        repo,
        tenant_key,
        call_id,
        publication_id,
        %CallDetailsObject{} = object
      ) do
    repo.transaction(fn ->
      with %Call{} = call <- fetch_call(repo, tenant_key, call_id, "FOR UPDATE"),
           {:ok, stored} <- fetch_publication(repo, call.id, publication_id),
           {:ok, publication} <- CallDetailsPublicationRecord.decode(stored, tenant_key, call_id),
           {:ok, published} <- CallDetailsPublication.publish(publication, object),
           {:ok, stored} <- persist_delivery(repo, stored, published),
           :ok <- CallDetailsPublicationHead.advance(repo, call, stored),
           {:ok, published} <-
             CallDetailsPublicationRecord.decode(stored, tenant_key, call_id) do
        published
      else
        nil -> repo.rollback(:call_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:publication_update_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def list_pending(repo, limit) when is_integer(limit) and limit > 0 do
    CallDetailsPublicationPending.list(repo, limit)
  end

  defp reserve_transaction(repo, tenant_key, call_id, snapshot) do
    with %Call{} = call <- fetch_call(repo, tenant_key, call_id, "FOR UPDATE"),
         :ok <- terminal(call),
         {:ok, result} <- existing_or_insert(repo, call, tenant_key, call_id, snapshot) do
      result
    else
      nil -> repo.rollback(:call_not_found)
      {:error, %Ecto.Changeset{}} -> repo.rollback(:publication_insert_failed)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp existing_or_insert(repo, call, tenant_key, call_id, snapshot) do
    case by_source(repo, call.id, snapshot.source_digest) do
      %StoredPublication{} = stored ->
        with {:ok, publication} <-
               CallDetailsPublicationRecord.decode(stored, tenant_key, call_id) do
          {:ok, {publication, :existing}}
        end

      nil ->
        insert_unless_filename_collision(repo, call, tenant_key, call_id, snapshot)
    end
  end

  defp insert_unless_filename_collision(repo, call, tenant_key, call_id, snapshot) do
    if by_filename(repo, call.id, snapshot.filename) do
      {:error, :publication_filename_conflict}
    else
      with {:ok, publication} <- CallDetailsPublication.pending(tenant_key, call_id, snapshot),
           {:ok, stored} <-
             repo.insert(CallDetailsPublicationRecord.reserve_changeset(call, publication)),
           {:ok, publication} <-
             CallDetailsPublicationRecord.decode(stored, tenant_key, call_id) do
        {:ok, {publication, :created}}
      end
    end
  end

  defp fetch_call(repo, tenant_key, call_id, "FOR UPDATE") do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call
      )

    repo.one(lock(query, "FOR UPDATE"))
  end

  defp fetch_publication(repo, call_key, publication_id) do
    case repo.one(
           from(publication in StoredPublication,
             where: publication.call_id == ^call_key and publication.public_id == ^publication_id
           )
         ) do
      nil -> {:error, :publication_not_found}
      stored -> {:ok, stored}
    end
  end

  defp by_source(repo, call_key, digest) do
    repo.one(
      from(publication in StoredPublication,
        where: publication.call_id == ^call_key and publication.source_digest == ^digest
      )
    )
  end

  defp by_filename(repo, call_key, filename) do
    repo.one(
      from(publication in StoredPublication,
        where: publication.call_id == ^call_key and publication.filename == ^filename,
        select: publication.id
      )
    )
  end

  defp terminal(%Call{state: state, ended_at: %DateTime{}}) when state in [:ended, :failed],
    do: :ok

  defp terminal(_call), do: {:error, :call_not_ended}

  defp persist_delivery(_repo, stored, %CallDetailsPublication{status: :published})
       when stored.status == :published do
    {:ok, stored}
  end

  defp persist_delivery(repo, stored, publication) do
    stored
    |> StoredPublication.publish_changeset(%{
      status: publication.status,
      object_key: publication.object_key,
      object_reference: publication.object_reference,
      published_at: publication.published_at
    })
    |> repo.update()
  end

end
