defmodule Vxpipe.Persistence.CallClaimStore do
  @moduledoc "Atomic prepared-web and outgoing claims in one tenant idempotency namespace."

  import Ecto.Query
  alias Ecto.Multi
  alias Vxpipe.Calls.PreparedCall
  alias Vxpipe.Persistence.{CallSpecId, PreparedCallRecord}
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

  def claim(repo, %PreparedCall{} = call, authorize) when is_function(authorize, 0) do
    if admissible?(call),
      do: insert(repo, call, authorize),
      else: {:error, :invalid_outgoing_call}
  end

  def claim(_repo, _call, _authorize), do: {:error, :invalid_outgoing_call}

  defp insert(repo, call, authorize) do
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

  defp admissible?(%PreparedCall{state: :admitting, plan: %{direction: :outgoing}}), do: true

  defp admissible?(%PreparedCall{state: :prepared, plan: %{direction: :incoming}} = call) do
    match?(
      %{connection: %{service: :web, mode: :receive, admission: :start_call}},
      Map.get(call.plan.participants, call.entry_caller)
    ) and
      Enum.count(call.participant_routes, fn {_key, ref} -> ref == call.entry_caller end) == 1
  end

  defp admissible?(_call), do: false

  defp selection(repo, call) do
    query =
      from(revision in StoredRevision,
        join: specification in assoc(revision, :call_spec),
        join: tenant in assoc(specification, :tenant),
        where:
          tenant.key == ^call.tenant_key and
            specification.id == ^CallSpecId.database_id(call.call_spec_id) and
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
