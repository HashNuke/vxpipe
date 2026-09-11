defmodule Vxpipe.CallEngine.Usage.ArchiveProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  @spec attributes(Observation.t()) :: keyword()
  def attributes(%Observation{} = observation) do
    attribution = observation.attribution

    [
      id: observation.id,
      participant_id: attribution.participant_id,
      activation_id: attribution.activation_id,
      correlation_id: attribution.turn_id,
      tool_call_id: attribution.tool_call_id,
      occurred_at: observation.observed_at,
      payload: payload(observation)
    ]
  end

  defp payload(observation) do
    compact(%{
      "attempt_id" => observation.attempt_id,
      "capability" => Atom.to_string(observation.capability),
      "delivery_id" => observation.delivery_id,
      "source_sequence" => observation.source_sequence,
      "outcome" => Atom.to_string(observation.outcome),
      "provider" => provider(observation.provider),
      "attribution" => attribution(observation.attribution),
      "measurement" => measurement(observation.measurement)
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
  defp unit(unit), do: Atom.to_string(unit)

  defp quantity(%Decimal{} = quantity), do: Decimal.to_string(quantity, :normal)
  defp quantity(quantity), do: quantity

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
