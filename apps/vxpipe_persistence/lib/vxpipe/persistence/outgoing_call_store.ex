defmodule Vxpipe.Persistence.OutgoingCallStore do
  @moduledoc false

  import Ecto.Query
  alias Vxpipe.Persistence.{CallClaimStore, PreparedCallRecord}
  alias Vxpipe.Persistence.Schema.Call

  defdelegate fetch_by_key(repo, tenant_key, key), to: CallClaimStore

  def claim(repo, %{state: :admitting, plan: %{direction: :outgoing}} = call, authorize),
    do: CallClaimStore.claim(repo, call, authorize)

  def claim(_repo, _call, _authorize), do: {:error, :invalid_outgoing_call}

  def mark_started(repo, expected, incarnation, started) do
    project(repo, expected, fn call ->
      with :ok <- Vxpipe.Persistence.CallIncarnationBinding.allow_start(call, incarnation),
           {:ok, call} <- Vxpipe.Persistence.CallIncarnationBinding.bind(repo, call, incarnation) do
        case call do
          %Call{state: :admitting} ->
            if DateTime.compare(started, call.created_at) in [:eq, :gt],
              do: repo.update(Call.start_changeset(call, incarnation, started)),
              else: {:error, :outgoing_start_conflict}

          %Call{state: state, incarnation_id: ^incarnation} when state in [:running, :ended] ->
            {:ok, call}

          _other ->
            {:error, :outgoing_start_conflict}
        end
      else
        {:error, :call_incarnation_mismatch} -> {:error, :outgoing_start_conflict}
        {:error, _reason} = error -> error
      end
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
end
