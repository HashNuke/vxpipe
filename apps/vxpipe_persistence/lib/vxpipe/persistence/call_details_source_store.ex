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

  alias Vxpipe.Persistence.Schema.{Call, CallDefinition, DefinitionRevision, TelephonyLeg, Tenant}

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
        join: revision in DefinitionRevision,
        on: revision.id == call.definition_revision_id,
        join: definition in CallDefinition,
        on: definition.id == revision.call_definition_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: {call, tenant, definition, revision}
      )

    case repo.one(query) do
      nil ->
        {:error, :call_not_found}

      {stored, tenant, definition, revision} ->
        with {:ok, call} <- PreparedCallRecord.load(stored, {tenant, definition, revision}) do
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
