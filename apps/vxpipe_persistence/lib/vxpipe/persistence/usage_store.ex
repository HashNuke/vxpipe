defmodule Vxpipe.Persistence.UsageStore do
  @moduledoc "Ecto adapter for immutable usage observations and rebuildable effective amounts."

  @behaviour Vxpipe.Calls.UsageRepository

  import Ecto.Query

  alias Vxpipe.CallEngine.Usage.{Observation, Settlement}
  alias Vxpipe.Persistence.{UsageAmountRecord, UsageObservationRecord}
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.UsageAmount, as: StoredAmount
  alias Vxpipe.Persistence.Schema.UsageObservation, as: StoredObservation

  @impl true
  def store_usage_observation(repo, %Observation{} = observation) do
    repo.transaction(fn ->
      with %Call{} = call <- fetch_call(repo, observation.tenant_id, observation.call_id, true),
           :ok <- storage_available(call),
           :ok <- incarnation_matches(call, observation),
           {:ok, stored} <- insert_or_deduplicate(repo, call, observation),
           {:ok, archived} <-
             UsageObservationRecord.decode(stored, observation.tenant_id, observation.call_id),
           :ok <- rebuild_amounts(repo, call, observation.tenant_id) do
        archived
      else
        nil -> repo.rollback(:call_not_found)
        {:error, %Ecto.Changeset{}} -> repo.rollback(:usage_observation_insert_failed)
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def fetch_usage_amounts(repo, tenant_key, call_id) do
    case fetch_call(repo, tenant_key, call_id, false) do
      nil ->
        {:error, :call_not_found}

      call ->
        call.id
        |> amount_query()
        |> repo.all()
        |> decode_amounts()
    end
  end

  defp fetch_call(repo, tenant_key, call_id, lock?) do
    query =
      from(call in Call,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: tenant.key == ^tenant_key and call.public_id == ^call_id,
        select: call
      )

    repo.one(if(lock?, do: lock(query, "FOR UPDATE"), else: query))
  end

  defp storage_available(%Call{state: state}) when state in [:admitting, :running, :ended],
    do: :ok

  defp storage_available(_call), do: {:error, :call_not_started}

  defp incarnation_matches(call, observation) do
    incarnation_id = observation.attribution.incarnation_id

    if is_nil(call.incarnation_id) or call.incarnation_id == incarnation_id,
      do: :ok,
      else: {:error, :call_incarnation_mismatch}
  end

  defp insert_or_deduplicate(repo, call, observation) do
    case repo.one(
           from(stored in StoredObservation,
             where: stored.call_id == ^call.id and stored.public_id == ^observation.id
           )
         ) do
      nil -> insert_observation(repo, call, observation)
      stored -> deduplicate(stored, observation)
    end
  end

  defp insert_observation(repo, call, observation) do
    %StoredObservation{}
    |> StoredObservation.changeset(UsageObservationRecord.attributes(call.id, observation))
    |> repo.insert()
  end

  defp deduplicate(stored, observation) do
    case UsageObservationRecord.decode(stored, observation.tenant_id, observation.call_id) do
      {:ok, ^observation} -> {:ok, stored}
      {:ok, _different} -> {:error, :usage_observation_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp rebuild_amounts(repo, call, tenant_key) do
    with {:ok, observations} <- fetch_observations(repo, call, tenant_key),
         {:ok, amounts} <- Settlement.effective_amounts(observations),
         {_, nil} <- repo.delete_all(from(amount in StoredAmount, where: amount.call_id == ^call.id)),
         :ok <- insert_amounts(repo, call, amounts) do
      :ok
    else
      {count, _returning} when is_integer(count) -> {:error, :usage_amount_delete_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_observations(repo, call, tenant_key) do
    stored =
      repo.all(
        from(observation in StoredObservation,
          where: observation.call_id == ^call.id,
          order_by: [asc: observation.observed_at, asc: observation.id]
        )
      )

    decode_observations(stored, tenant_key, call.public_id)
  end

  defp decode_observations(stored, tenant_key, call_id) do
    decode(stored, &UsageObservationRecord.decode(&1, tenant_key, call_id))
  end

  defp insert_amounts(repo, call, amounts) do
    Enum.reduce_while(amounts, :ok, fn amount, :ok ->
      result =
        %StoredAmount{}
        |> StoredAmount.changeset(UsageAmountRecord.attributes(call.id, amount))
        |> repo.insert()

      case result do
        {:ok, _stored} -> {:cont, :ok}
        {:error, %Ecto.Changeset{}} -> {:halt, {:error, :usage_amount_insert_failed}}
      end
    end)
  end

  defp amount_query(call_id) do
    from(amount in StoredAmount,
      where: amount.call_id == ^call_id,
      order_by: [asc: amount.component, asc: amount.public_id]
    )
  end

  defp decode_amounts(stored), do: decode(stored, &UsageAmountRecord.decode/1)

  defp decode(records, decoder) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, decoded} ->
      case decoder.(record) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _reason} = error -> error
    end
  end
end
