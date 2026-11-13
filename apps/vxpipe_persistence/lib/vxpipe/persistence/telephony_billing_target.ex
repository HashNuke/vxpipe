defmodule Vxpipe.Persistence.TelephonyBillingTarget do
  @moduledoc false

  import Ecto.Query

  alias Vxpipe.CallEngine.Telephony.ServiceReference
  alias Vxpipe.Persistence.{ResolvedPlanCodec, UsageObservationRecord}
  alias Vxpipe.Persistence.Schema.{Call, Tenant, UsageObservation}

  def fetch(repo, provider, leg_id, session_id) do
    query =
      from(observation in UsageObservation,
        join: call in Call,
        on: call.id == observation.call_id,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: observation.capability == :telephony,
        where: fragment("?->>'name'", observation.provider) == ^provider,
        where: fragment("?->>'operation_id'", observation.provider) == ^leg_id,
        where: fragment("?->>'session_id'", observation.provider) == ^session_id,
        distinct: [observation.call_id, observation.attempt_id],
        order_by: [asc: observation.call_id, asc: observation.attempt_id, asc: observation.id],
        limit: 2,
        select: {observation, call, tenant.key}
      )

    case repo.all(query) do
      [{stored, call, tenant}] -> target(stored, call, tenant)
      [] -> {:error, :usage_target_not_found}
      _ambiguous -> {:error, :ambiguous_usage_target}
    end
  end

  defp target(stored, call, tenant) do
    with {:ok, observation} <- UsageObservationRecord.decode(stored, tenant, call.public_id),
         {:ok, plan} <- ResolvedPlanCodec.decode(call.resolved_plan),
         {:ok, reference} <- reference(plan, observation) do
      {:ok, {observation, reference}}
    end
  end

  defp reference(plan, observation) do
    references =
      plan.participants
      |> Map.values()
      |> Enum.map(& &1.telephony_service)
      |> Enum.filter(fn
        %ServiceReference{} = ref ->
          ref.tenant_id == observation.tenant_id and
            ref.name == observation.provider.integration_id and
            ref.provider == observation.provider.name

        _ ->
          false
      end)
      |> Enum.uniq()

    case references do
      [reference] -> {:ok, reference}
      _unavailable -> {:error, :usage_service_not_found}
    end
  end
end
