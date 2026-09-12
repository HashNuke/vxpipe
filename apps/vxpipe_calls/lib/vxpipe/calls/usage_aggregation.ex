defmodule Vxpipe.Calls.UsageAggregation do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.EffectiveAmount
  alias Vxpipe.Calls.UsageTotal

  @spec derive([EffectiveAmount.t()]) :: [UsageTotal.t()]
  def derive(amounts) when is_list(amounts) do
    amounts
    |> Enum.filter(&root_amount?/1)
    |> Enum.group_by(&dimension_key/1)
    |> Enum.map(fn {_key, grouped} -> total(grouped) end)
    |> Enum.sort_by(&sort_key/1)
  end

  defp root_amount?(%EffectiveAmount{included_in: nil}), do: true
  defp root_amount?(%EffectiveAmount{}), do: false
  defp root_amount?(_invalid), do: false

  defp dimension_key(amount) do
    provider = amount.provider
    attribution = amount.attribution

    {
      amount.capability,
      provider.name,
      provider.integration_id,
      provider.model,
      provider.voice,
      attribution.participant_id,
      attribution.activation_id,
      attribution.service_interval_id,
      attribution.leg_id,
      attribution.turn_id,
      attribution.utterance_id,
      attribution.tool_call_id,
      amount.unit,
      amount.provenance
    }
  end

  defp total([first | rest]) do
    quantity = Enum.reduce(rest, first.quantity, &add(&1.quantity, &2))
    provider = first.provider
    attribution = first.attribution

    %UsageTotal{
      capability: first.capability,
      provider_name: provider.name,
      integration_id: provider.integration_id,
      model: provider.model,
      voice: provider.voice,
      participant_id: attribution.participant_id,
      activation_id: attribution.activation_id,
      service_interval_id: attribution.service_interval_id,
      leg_id: attribution.leg_id,
      turn_id: attribution.turn_id,
      utterance_id: attribution.utterance_id,
      tool_call_id: attribution.tool_call_id,
      unit: first.unit,
      quantity: quantity,
      provenance: first.provenance,
      amount_count: length(rest) + 1
    }
  end

  defp add(%Decimal{} = left, %Decimal{} = right), do: Decimal.add(left, right)
  defp add(left, right) when is_integer(left) and is_integer(right), do: left + right

  defp sort_key(total) do
    {
      total.capability,
      total.provider_name,
      total.integration_id,
      total.model,
      total.voice,
      total.participant_id,
      total.activation_id,
      total.service_interval_id,
      total.leg_id,
      total.turn_id,
      total.utterance_id,
      total.tool_call_id,
      total.unit,
      total.provenance
    }
  end
end
