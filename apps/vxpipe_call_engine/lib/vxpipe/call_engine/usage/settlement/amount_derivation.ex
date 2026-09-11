defmodule Vxpipe.CallEngine.Usage.Settlement.AmountDerivation do
  @moduledoc "Derives one effective amount for each attempt, component, unit, and provenance."

  alias Vxpipe.CallEngine.Usage.{EffectiveAmount, Observation}
  alias Vxpipe.CallEngine.Usage.Settlement.DeliveryDeduplication

  @type error ::
          :conflicting_delivery | :mixed_measurement_modes | :ambiguous_cumulative_order

  @spec derive([Observation.t()]) :: {:ok, [EffectiveAmount.t()]} | {:error, error()}
  def derive(observations) do
    observations
    |> Enum.group_by(&amount_key/1)
    |> Enum.reduce_while({:ok, []}, fn {_key, grouped}, {:ok, amounts} ->
      case derive_amount(grouped) do
        {:ok, amount} -> {:cont, {:ok, [amount | amounts]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp derive_amount(observations) do
    with {:ok, observations} <- DeliveryDeduplication.deduplicate(observations),
         [mode] <- observations |> Enum.map(& &1.measurement.mode) |> Enum.uniq(),
         {:ok, quantity, status, source_ids} <- settle(mode, observations) do
      first = hd(observations)

      {:ok,
       %EffectiveAmount{
         attempt_id: first.attempt_id,
         capability: first.capability,
         provider: first.provider,
         attribution: first.attribution,
         component: first.measurement.component,
         unit: first.measurement.unit,
         quantity: quantity,
         mode: mode,
         status: status,
         provenance: first.measurement.provenance,
         included_in: first.measurement.included_in,
         observation_ids: source_ids
       }}
    else
      modes when is_list(modes) -> {:error, :mixed_measurement_modes}
      {:error, reason} -> {:error, reason}
    end
  end

  defp settle(:delta, observations) do
    quantity =
      observations
      |> Enum.map(& &1.measurement.quantity)
      |> sum()

    status =
      cond do
        Enum.any?(observations, &(&1.measurement.status == :estimate)) -> :estimate
        Enum.any?(observations, &(&1.measurement.status == :correction)) -> :correction
        true -> :final
      end

    {:ok, quantity, status, Enum.map(observations, & &1.id)}
  end

  defp settle(:cumulative, observations) do
    status =
      observations
      |> Enum.map(& &1.measurement.status)
      |> Enum.max_by(&status_rank/1)

    candidates = Enum.filter(observations, &(&1.measurement.status == status))

    with {:ok, selected} <- latest_cumulative(candidates) do
      {:ok, selected.measurement.quantity, status, [selected.id]}
    end
  end

  defp latest_cumulative([observation]), do: {:ok, observation}

  defp latest_cumulative(observations) do
    if Enum.all?(observations, &is_integer(&1.source_sequence)) do
      {:ok, Enum.max_by(observations, & &1.source_sequence)}
    else
      {:error, :ambiguous_cumulative_order}
    end
  end

  defp amount_key(observation) do
    measurement = observation.measurement

    {
      observation.attempt_id,
      observation.capability,
      observation.provider,
      observation.attribution,
      measurement.component,
      measurement.unit,
      measurement.provenance,
      measurement.included_in
    }
  end

  defp status_rank(:estimate), do: 1
  defp status_rank(:final), do: 2
  defp status_rank(:correction), do: 3

  defp sum([first | rest]), do: Enum.reduce(rest, first, &add/2)

  defp add(%Decimal{} = left, %Decimal{} = right), do: Decimal.add(left, right)
  defp add(left, right) when is_integer(left) and is_integer(right), do: left + right
end
