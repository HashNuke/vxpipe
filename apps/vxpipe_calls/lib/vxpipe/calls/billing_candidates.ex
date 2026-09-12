defmodule Vxpipe.Calls.BillingCandidates do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Observation, ProviderContext}
  alias Vxpipe.Calls.BillingLookupRequest

  @external_fields [:request_id, :operation_id, :session_id]

  @spec build([Observation.t()], String.t(), String.t()) ::
          {:ok,
           %{
             candidate_count: non_neg_integer(),
             requests: [BillingLookupRequest.t()],
             missing_reference_count: non_neg_integer(),
             unavailable_count: non_neg_integer()
           }}
          | {:error, :invalid_usage_observations}
  def build(observations, tenant_key, call_id)
      when is_list(observations) and is_binary(tenant_key) and is_binary(call_id) do
    if Enum.all?(observations, &valid_scope?(&1, tenant_key, call_id)) do
      groups = Enum.group_by(observations, &candidate_key/1)

      summary =
        groups
        |> Enum.sort_by(fn {key, _observations} -> key end)
        |> Enum.reduce(empty_summary(map_size(groups)), &add_candidate/2)

      {:ok, %{summary | requests: Enum.reverse(summary.requests)}}
    else
      {:error, :invalid_usage_observations}
    end
  end

  def build(_observations, _tenant_key, _call_id), do: {:error, :invalid_usage_observations}

  defp empty_summary(candidate_count) do
    %{
      candidate_count: candidate_count,
      requests: [],
      missing_reference_count: 0,
      unavailable_count: 0
    }
  end

  defp add_candidate({_key, observations}, summary) do
    with {:ok, provider} <- merge_provider_references(observations),
         latest <- latest(observations),
         {:ok, request} <- request(latest, provider) do
      %{summary | requests: [request | summary.requests]}
    else
      {:error, :missing_provider_reference} ->
        %{summary | missing_reference_count: summary.missing_reference_count + 1}

      {:error, _reason} ->
        %{summary | unavailable_count: summary.unavailable_count + 1}
    end
  end

  defp request(observation, provider) do
    BillingLookupRequest.new(
      tenant_key: observation.tenant_id,
      call_id: observation.call_id,
      attempt_id: observation.attempt_id,
      capability: observation.capability,
      provider: provider,
      attribution: observation.attribution,
      outcome: observation.outcome
    )
  end

  defp merge_provider_references([first | _rest] = observations) do
    values =
      Enum.reduce_while(@external_fields, {:ok, %{}}, fn field, {:ok, merged} ->
        case observations |> Enum.map(&Map.fetch!(&1.provider, field)) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
          [] -> {:cont, {:ok, Map.put(merged, field, nil)}}
          [value] -> {:cont, {:ok, Map.put(merged, field, value)}}
          _conflict -> {:halt, {:error, :conflicting_provider_reference}}
        end
      end)

    with {:ok, values} <- values,
         true <- Enum.any?(@external_fields, &is_binary(Map.fetch!(values, &1))),
         {:ok, provider} <-
           ProviderContext.new(
             name: first.provider.name,
             integration_id: first.provider.integration_id,
             model: first.provider.model,
             voice: first.provider.voice,
             request_id: values.request_id,
             operation_id: values.operation_id,
             session_id: values.session_id
           ) do
      {:ok, provider}
    else
      false -> {:error, :missing_provider_reference}
      {:error, reason} -> {:error, reason}
    end
  end

  defp latest(observations) do
    Enum.max_by(observations, fn observation ->
      {
        DateTime.to_unix(observation.observed_at, :microsecond),
        observation.source_sequence || -1,
        observation.id
      }
    end)
  end

  defp valid_scope?(%Observation{tenant_id: tenant_key, call_id: call_id}, tenant_key, call_id),
    do: true

  defp valid_scope?(_observation, _tenant_key, _call_id), do: false

  defp candidate_key(observation) do
    provider = observation.provider

    {
      observation.tenant_id,
      observation.call_id,
      observation.attempt_id,
      observation.capability,
      provider.name,
      provider.integration_id,
      provider.model,
      provider.voice,
      observation.attribution
    }
  end
end
