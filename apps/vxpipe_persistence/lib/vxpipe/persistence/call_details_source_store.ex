defmodule Vxpipe.Persistence.CallDetailsSourceStore do
  @moduledoc false

  import Ecto.Query

  alias Vxpipe.Persistence.{
    ArchiveStore,
    ArtifactStore,
    CallDetailsSourceRead,
    PreparedCallRecord,
    UsageStore
  }

  alias Vxpipe.Calls.PreparedCall

  alias Vxpipe.Persistence.Schema.{Call, CallSpec, CallSpecRevision, TelephonyLeg, Tenant}

  @spec read(module(), String.t(), String.t()) ::
          {:ok, CallDetailsSourceRead.t()} | {:error, term()}
  def read(repo, tenant_key, call_id) do
    with {:ok, call, call_key} <- fetch_call(repo, tenant_key, call_id),
         :ok <- terminal(call),
         {:ok, facts} <- ArchiveStore.fetch_call_facts(repo, tenant_key, call_id),
         {:ok, snapshots} <- ArchiveStore.fetch_variable_snapshots(repo, tenant_key, call_id),
         {:ok, artifacts} <- ArtifactStore.fetch_call_artifacts(repo, tenant_key, call_id),
         {:ok, observations} <- UsageStore.fetch_usage_observations(repo, tenant_key, call_id),
         {:ok, amounts} <- UsageStore.fetch_usage_amounts(repo, tenant_key, call_id) do
      {:ok,
       %CallDetailsSourceRead{
         call: call,
         facts: facts,
         variable_snapshots: snapshots,
         artifacts: artifacts,
         usage_observations: observations,
         usage_amounts: amounts,
         telephony_legs: telephony_legs(repo, call_key)
       }}
    end
  end

  defp fetch_call(repo, tenant_key, call_id) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        join: revision in CallSpecRevision,
        on: revision.id == call.call_spec_revision_id,
        join: call_spec in CallSpec,
        on: call_spec.id == revision.call_spec_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: {call, tenant, call_spec, revision}
      )

    case repo.one(query) do
      nil ->
        {:error, :call_not_found}

      {stored, tenant, call_spec, revision} ->
        with {:ok, call} <- PreparedCallRecord.load(stored, {tenant, call_spec, revision}) do
          {:ok, call, stored.id}
        end
    end
  end

  defp terminal(%PreparedCall{state: state, ended_at: %DateTime{}})
       when state in [:ended, :failed],
       do: :ok

  defp terminal(_call), do: {:error, :call_not_ended}

  defp telephony_legs(repo, call_key) do
    repo.all(
      from(leg in TelephonyLeg,
        where: leg.call_id == ^call_key,
        order_by: [asc: leg.accepted_at, asc: leg.id]
      )
    )
  end
end
