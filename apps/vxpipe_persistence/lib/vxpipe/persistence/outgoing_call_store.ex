defmodule Vxpipe.Persistence.OutgoingCallStore do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias Vxpipe.Persistence.PreparedCallRecord
  alias Vxpipe.Persistence.Schema.Call
  alias Vxpipe.Persistence.Schema.CallSpecRevision, as: StoredRevision

  def fetch_by_key(repo, tenant_key, key) when is_binary(key) do
    query =
      from(call in Call,
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :call_spec_revision),
        join: specification in assoc(revision, :call_spec),
        where: tenant.key == ^tenant_key and call.idempotency_key == ^key,
        select: {call, {tenant, specification, revision}}
      )

    case repo.one(query) do
      nil -> {:error, :not_found}
      {call, selection} -> PreparedCallRecord.load(call, selection)
    end
  end

  def claim(repo, %{state: :admitting, plan: %{direction: :outgoing}} = call, authorize)
      when is_function(authorize, 0) do
    multi =
      Multi.new()
      |> Multi.run(:selection, fn repo, _changes -> selection(repo, call) end)
      |> Multi.run(:credentials, fn _repo, _changes -> authorize.() end)
      |> Multi.insert(:call, fn %{selection: {tenant, _specification, revision}} ->
        PreparedCallRecord.changeset(call, tenant, revision)
      end)

    case repo.transaction(multi) do
      {:ok, %{call: stored, selection: selection}} -> PreparedCallRecord.load(stored, selection)
      {:error, :call, changeset, _changes} -> insertion_error(repo, call, changeset)
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def claim(_repo, _call, _authorize), do: {:error, :invalid_outgoing_call}

  def mark_started(repo, expected, incarnation, started) do
    project(repo, expected, fn
      %Call{state: :admitting} = call ->
        if DateTime.compare(started, call.created_at) in [:eq, :gt],
          do: repo.update(Call.start_changeset(call, incarnation, started)),
          else: {:error, :outgoing_start_conflict}

      %Call{state: state, incarnation_id: ^incarnation} = call when state in [:running, :ended] ->
        {:ok, call}

      _call ->
        {:error, :outgoing_start_conflict}
    end)
  end

  def mark_failed(repo, expected, reason, ended) do
    project(repo, expected, fn
      %Call{state: state} = call when state in [:admitting, :running] ->
        outcome =
          call.outgoing_outcome || if(reason == :startup_unknown, do: :unknown, else: :failed)

        call
        |> Call.failure_changeset(reason, ended)
        |> Ecto.Changeset.change(outgoing_outcome: outcome)
        |> repo.update()

      call ->
        {:ok, call}
    end)
  end

  defp project(repo, expected, operation) do
    query =
      from(call in Call,
        join: tenant in assoc(call, :tenant),
        join: revision in assoc(call, :call_spec_revision),
        join: specification in assoc(revision, :call_spec),
        where: tenant.key == ^expected.tenant_key and call.public_id == ^expected.id,
        lock: "FOR UPDATE OF c0",
        select: {call, {tenant, specification, revision}}
      )

    repo.transaction(fn ->
      with {call, selection} <- repo.one(query),
           true <- call.plan_digest == expected.plan_digest,
           {:ok, loaded} <- PreparedCallRecord.load(call, selection),
           true <- loaded.plan.direction == :outgoing,
           {:ok, updated} <- operation.(call),
           {:ok, result} <- PreparedCallRecord.load(updated, selection) do
        result
      else
        nil -> repo.rollback(:not_found)
        false -> repo.rollback(:outgoing_call_mismatch)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:outgoing_projection_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  defp selection(repo, call) do
    query =
      from(revision in StoredRevision,
        join: specification in assoc(revision, :call_spec),
        join: tenant in assoc(specification, :tenant),
        where:
          tenant.key == ^call.tenant_key and specification.public_id == ^call.call_spec_id and
            revision.revision == ^call.call_spec_revision,
        select: {tenant, specification, revision}
      )

    case repo.one(query) do
      nil -> {:error, :call_spec_revision_not_found}
      selection -> {:ok, selection}
    end
  end

  defp insertion_error(repo, call, changeset) do
    idempotency_conflict? =
      Enum.any?(changeset.errors, fn
        {:idempotency_key, {_message, metadata}} -> Keyword.get(metadata, :constraint) == :unique
        _error -> false
      end)

    if idempotency_conflict? do
      case fetch_by_key(repo, call.tenant_key, call.idempotency_key) do
        {:ok, %{idempotency_digest: digest} = existing} when digest == call.idempotency_digest ->
          {:duplicate, existing}

        {:ok, _existing} ->
          {:error, :idempotency_conflict}

        {:error, _reason} ->
          {:error, :call_insert_failed}
      end
    else
      if Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
           Keyword.get(metadata, :constraint) == :unique
         end), do: {:error, :call_id_conflict}, else: {:error, :call_insert_failed}
    end
  end
end
