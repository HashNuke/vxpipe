defmodule Vxpipe.CallEngine.Usage.Settlement.DeliveryDeduplication do
  @moduledoc """
  Deduplicates observations only when stable observation, delivery, or source-sequence evidence
  proves a replay.
  """

  alias Vxpipe.CallEngine.Usage.Observation

  @spec deduplicate([Observation.t()]) ::
          {:ok, [Observation.t()]} | {:error, :conflicting_delivery}
  def deduplicate(observations) do
    with {:ok, observations} <- deduplicate_by(observations, & &1.id),
         {:ok, observations} <- deduplicate_by(observations, & &1.delivery_id),
         {:ok, observations} <- deduplicate_by(observations, & &1.source_sequence) do
      {:ok, observations}
    end
  end

  defp deduplicate_by(observations, identity) do
    observations
    |> Enum.reduce_while({:ok, %{}, []}, fn observation, {:ok, seen, unique} ->
      case identity.(observation) do
        nil ->
          {:cont, {:ok, seen, [observation | unique]}}

        key ->
          fingerprint = observation_fingerprint(observation)

          case Map.fetch(seen, key) do
            :error ->
              {:cont, {:ok, Map.put(seen, key, fingerprint), [observation | unique]}}

            {:ok, ^fingerprint} ->
              {:cont, {:ok, seen, unique}}

            {:ok, _different} ->
              {:halt, {:error, :conflicting_delivery}}
          end
      end
    end)
    |> case do
      {:ok, _seen, unique} -> {:ok, Enum.reverse(unique)}
      error -> error
    end
  end

  defp observation_fingerprint(observation) do
    {
      observation.tenant_id,
      observation.call_id,
      observation.attempt_id,
      observation.capability,
      observation.provider,
      observation.attribution,
      observation.measurement,
      observation.outcome
    }
  end
end
