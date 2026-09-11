defmodule Vxpipe.Persistence.ArtifactStore do
  @moduledoc "Ecto adapter for terminal call-artifact metadata."

  @behaviour Vxpipe.Calls.ArtifactRepository

  import Ecto.Query

  alias Vxpipe.Calls.CallArtifact
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.CallArtifact, as: StoredArtifact

  @impl true
  def store_call_artifact(repo, %CallArtifact{} = artifact) do
    repo.transaction(fn ->
      with %Call{} = call <- fetch_call(repo, artifact.tenant_key, artifact.call_id, "FOR UPDATE"),
           :ok <- storage_available(call),
           :ok <- incarnation_matches(repo, call, artifact.incarnation_id),
           {:ok, stored} <- insert_or_deduplicate(repo, call, artifact),
           {:ok, archived} <- to_call_artifact(stored, artifact.tenant_key, artifact.call_id) do
        archived
      else
        nil -> repo.rollback(:call_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:call_artifact_insert_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def fetch_call_artifacts(repo, tenant_key, call_id) do
    case fetch_call(repo, tenant_key, call_id) do
      nil ->
        {:error, :call_not_found}

      call ->
        call.id
        |> artifacts_query()
        |> repo.all()
        |> convert_artifacts(tenant_key, call_id)
    end
  end

  defp fetch_call(repo, tenant_key, call_id, lock \\ nil) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call
      )

    repo.one(with_lock(query, lock))
  end

  defp with_lock(query, nil), do: query
  defp with_lock(query, "FOR UPDATE"), do: lock(query, "FOR UPDATE")

  defp artifacts_query(call_id) do
    from(artifact in StoredArtifact,
      where: artifact.call_id == ^call_id,
      order_by: [asc: artifact.inserted_at, asc: artifact.id]
    )
  end

  defp storage_available(%Call{state: state}) when state in [:admitting, :running, :ended],
    do: :ok

  defp storage_available(_call), do: {:error, :call_not_started}

  defp incarnation_matches(repo, call, incarnation_id) do
    existing =
      repo.one(
        from(artifact in StoredArtifact,
          where: artifact.call_id == ^call.id,
          select: artifact.incarnation_id,
          limit: 1
        )
      )

    expected = call.incarnation_id || existing

    if is_nil(expected) or expected == incarnation_id,
      do: :ok,
      else: {:error, :call_incarnation_mismatch}
  end

  defp insert_or_deduplicate(repo, call, artifact) do
    case repo.one(
           from(stored in StoredArtifact,
             where: stored.call_id == ^call.id and stored.public_id == ^artifact.id
           )
         ) do
      nil -> repo.insert(changeset(call, artifact))
      stored -> deduplicate(stored, artifact)
    end
  end

  defp deduplicate(stored, artifact) do
    case to_call_artifact(stored, artifact.tenant_key, artifact.call_id) do
      {:ok, ^artifact} -> {:ok, stored}
      {:ok, _different} -> {:error, :call_artifact_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp changeset(call, artifact) do
    StoredArtifact.changeset(%StoredArtifact{}, %{
      public_id: artifact.id,
      call_id: call.id,
      room_id: artifact.room_id,
      incarnation_id: artifact.incarnation_id,
      kind: artifact.kind,
      participant_id: artifact.participant_id,
      connection_id: artifact.connection_id,
      track_id: artifact.track_id,
      object_key: artifact.object_key,
      object_reference: artifact.object_reference,
      sample_rate: artifact.sample_rate,
      channels: artifact.channels,
      sample_format: artifact.sample_format,
      started_offset_samples: artifact.started_offset_samples,
      ended_offset_samples: artifact.ended_offset_samples,
      sample_count: artifact.sample_count,
      accepted_chunks: artifact.accepted_chunks,
      rejected_chunks: artifact.rejected_chunks,
      gaps: %{"intervals" => artifact.gaps},
      status: artifact.status,
      terminal_reason: artifact.terminal_reason
    })
  end

  defp to_call_artifact(stored, tenant_key, call_id) do
    CallArtifact.new(
      id: stored.public_id,
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: stored.room_id,
      incarnation_id: stored.incarnation_id,
      kind: stored.kind,
      participant_id: stored.participant_id,
      connection_id: stored.connection_id,
      track_id: stored.track_id,
      object_key: stored.object_key,
      object_reference: stored.object_reference,
      sample_rate: stored.sample_rate,
      channels: stored.channels,
      sample_format: stored.sample_format,
      started_offset_samples: stored.started_offset_samples,
      ended_offset_samples: stored.ended_offset_samples,
      sample_count: stored.sample_count,
      accepted_chunks: stored.accepted_chunks,
      rejected_chunks: stored.rejected_chunks,
      gaps: Map.get(stored.gaps, "intervals", []),
      status: stored.status,
      terminal_reason: stored.terminal_reason
    )
  end

  defp convert_artifacts(stored, tenant_key, call_id) do
    Enum.reduce_while(stored, {:ok, []}, fn artifact, {:ok, artifacts} ->
      case to_call_artifact(artifact, tenant_key, call_id) do
        {:ok, value} -> {:cont, {:ok, artifacts ++ [value]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
