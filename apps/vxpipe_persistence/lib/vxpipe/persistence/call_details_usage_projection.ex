defmodule Vxpipe.Persistence.CallDetailsUsageProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    EffectiveAmount,
    Measurement,
    Observation,
    ProviderContext
  }

  alias Vxpipe.Calls.{UsageReport, UsageTotal}
  alias Vxpipe.Persistence.CallDetailsTimestamp

  @spec project([Observation.t()], [EffectiveAmount.t()]) :: {:ok, map()} | {:error, term()}
  def project(observations, amounts) when is_list(observations) and is_list(amounts) do
    with {:ok, report} <- UsageReport.new(amounts) do
      {:ok,
       %{
         "observations" => Enum.map(observations, &observation/1),
         "amounts" => Enum.map(amounts, &amount/1),
         "totals" => Enum.map(report.totals, &total/1)
       }}
    end
  end

  defp observation(%Observation{} = observation) do
    compact(%{
      "id" => observation.id,
      "delivery_id" => observation.delivery_id,
      "source_sequence" => observation.source_sequence,
      "attempt_id" => observation.attempt_id,
      "capability" => Atom.to_string(observation.capability),
      "provider" => provider(observation.provider),
      "attribution" => attribution(observation.attribution),
      "measurement" => measurement(observation.measurement),
      "outcome" => Atom.to_string(observation.outcome),
      "observed_at" => CallDetailsTimestamp.format(observation.observed_at)
    })
  end

  defp amount(%EffectiveAmount{} = amount) do
    compact(%{
      "attempt_id" => amount.attempt_id,
      "capability" => Atom.to_string(amount.capability),
      "provider" => provider(amount.provider),
      "attribution" => attribution(amount.attribution),
      "component" => amount.component,
      "unit" => unit(amount.unit),
      "quantity" => quantity(amount.quantity),
      "mode" => Atom.to_string(amount.mode),
      "status" => Atom.to_string(amount.status),
      "provenance" => Atom.to_string(amount.provenance),
      "included_in" => amount.included_in,
      "observation_ids" => amount.observation_ids
    })
  end

  defp total(%UsageTotal{} = total) do
    compact(%{
      "capability" => Atom.to_string(total.capability),
      "provider_name" => total.provider_name,
      "integration_id" => total.integration_id,
      "model" => total.model,
      "voice" => total.voice,
      "participant_id" => total.participant_id,
      "activation_id" => total.activation_id,
      "service_interval_id" => total.service_interval_id,
      "leg_id" => total.leg_id,
      "turn_id" => total.turn_id,
      "utterance_id" => total.utterance_id,
      "tool_call_id" => total.tool_call_id,
      "unit" => unit(total.unit),
      "quantity" => quantity(total.quantity),
      "provenance" => Atom.to_string(total.provenance),
      "amount_count" => total.amount_count
    })
  end

  defp provider(%ProviderContext{} = provider) do
    compact(%{
      "name" => provider.name,
      "integration_id" => provider.integration_id,
      "model" => provider.model,
      "voice" => provider.voice,
      "request_id" => provider.request_id,
      "operation_id" => provider.operation_id,
      "session_id" => provider.session_id
    })
  end

  defp attribution(%Attribution{} = attribution) do
    compact(%{
      "room_id" => attribution.room_id,
      "incarnation_id" => attribution.incarnation_id,
      "participant_id" => attribution.participant_id,
      "activation_id" => attribution.activation_id,
      "service_interval_id" => attribution.service_interval_id,
      "leg_id" => attribution.leg_id,
      "turn_id" => attribution.turn_id,
      "utterance_id" => attribution.utterance_id,
      "tool_call_id" => attribution.tool_call_id
    })
  end

  defp measurement(nil), do: nil

  defp measurement(%Measurement{} = measurement) do
    compact(%{
      "component" => measurement.component,
      "unit" => unit(measurement.unit),
      "quantity" => quantity(measurement.quantity),
      "mode" => Atom.to_string(measurement.mode),
      "status" => Atom.to_string(measurement.status),
      "provenance" => Atom.to_string(measurement.provenance),
      "included_in" => measurement.included_in
    })
  end

  defp unit({:currency, currency}), do: %{"currency" => currency}
  defp unit(value), do: Atom.to_string(value)

  defp quantity(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp quantity(value), do: value

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
