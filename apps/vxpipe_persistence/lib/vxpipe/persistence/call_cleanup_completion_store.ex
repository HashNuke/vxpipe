defmodule Vxpipe.Persistence.CallCleanupCompletionStore do
  @moduledoc "Acknowledges the managed incarnation under its call lock and replays terminal evidence."

  import Ecto.Query
  alias Vxpipe.Persistence.{ArchiveRecordCodec, CallEndProjection, PreparedCallRecord}
  alias Vxpipe.Persistence.Schema.{Call, CallFact}

  def complete(repo, binding, completed_at) do
    case Ecto.UUID.cast(binding.call_id) do
      {:ok, id} when id == binding.call_id -> complete_locked(repo, binding, completed_at)
      _invalid -> {:error, :not_found}
    end
  end

  defp complete_locked(repo, binding, completed_at) do
    repo.transaction(fn ->
      query =
        from(call in Call,
          join: tenant in assoc(call, :tenant),
          join: revision in assoc(call, :call_spec_revision),
          join: specification in assoc(revision, :call_spec),
          where: tenant.key == ^binding.tenant_key and call.public_id == ^binding.call_id,
          lock: "FOR UPDATE OF c0",
          select: {call, {tenant, specification, revision}}
        )

      with {call, selection} <- repo.one(query),
           :ok <- validate(call, binding, completed_at),
           {:ok, acknowledged} <- acknowledge(repo, call, completed_at),
           {:ok, projected} <- project(repo, acknowledged, binding.tenant_key),
           {:ok, result} <- PreparedCallRecord.load(projected, selection) do
        result
      else
        nil -> repo.rollback(:not_found)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp validate(call, binding, completed_at) do
    cond do
      not call.gateway_cleanup_required ->
        {:error, :cleanup_reservation_unavailable}

      call.room_id != binding.room_id ->
        {:error, :call_room_mismatch}

      call.incarnation_id != binding.incarnation_id or not call.incarnation_binding_verified ->
        {:error, :call_incarnation_mismatch}

      DateTime.compare(completed_at, call.created_at) == :lt or
          (not is_nil(call.started_at) and DateTime.compare(completed_at, call.started_at) == :lt) ->
        {:error, :invalid_call_cleanup}

      true ->
        :ok
    end
  end

  defp acknowledge(_repo, %Call{gateway_cleanup_completed_at: %DateTime{}} = call, _time),
    do: {:ok, call}

  defp acknowledge(repo, call, time) do
    call |> Call.cleanup_completion_changeset(time) |> repo.update()
  end

  defp project(_repo, %Call{state: :ended} = call, _tenant), do: {:ok, call}

  defp project(repo, %Call{hangup_requested_at: %DateTime{}} = call, _tenant) do
    call |> Call.cleanup_cancellation_changeset() |> repo.update()
  end

  defp project(_repo, %Call{state: :failed} = call, _tenant), do: {:ok, call}

  defp project(repo, call, tenant) do
    close =
      repo.one(
        from(fact in CallFact,
          where:
            fact.call_id == ^call.id and fact.room_id == ^call.room_id and
              fact.incarnation_id == ^call.incarnation_id and fact.kind == "archive_stream_closed",
          order_by: [asc: fact.sequence],
          limit: 1
        )
      )

    case close do
      nil ->
        {:ok, call}

      stored ->
        with {:ok, fact} <- ArchiveRecordCodec.call_fact(stored, tenant, call.public_id),
             do: CallEndProjection.apply(repo, call, fact)
    end
  end
end
