defmodule Vxpipe.Calls.UsageObservationProjection do
  @moduledoc "Restores typed usage observations from their private call-fact representation."

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}
  alias Vxpipe.Calls.CallFact

  @spec project(CallFact.t()) ::
          {:ok, Observation.t()} | {:error, :invalid_usage_observation_fact}
  def project(%CallFact{kind: :usage_observed, payload: payload} = fact) when is_map(payload) do
    with {:ok, provider} <- provider(Map.get(payload, "provider")),
         {:ok, attribution} <- attribution(Map.get(payload, "attribution")),
         :ok <- matching_envelope(attribution, fact),
         {:ok, measurement} <- measurement(Map.get(payload, "measurement")),
         {:ok, capability} <- capability(Map.get(payload, "capability")),
         {:ok, outcome} <- outcome(Map.get(payload, "outcome")),
         {:ok, observation} <-
           Observation.new(
             id: fact.id,
             delivery_id: Map.get(payload, "delivery_id"),
             source_sequence: Map.get(payload, "source_sequence"),
             tenant_id: fact.tenant_key,
             call_id: fact.call_id,
             attempt_id: Map.get(payload, "attempt_id"),
             capability: capability,
             provider: provider,
             attribution: attribution,
             measurement: measurement,
             outcome: outcome,
             observed_at: fact.occurred_at
           ) do
      {:ok, observation}
    else
      _invalid -> {:error, :invalid_usage_observation_fact}
    end
  end

  def project(%CallFact{}), do: {:error, :invalid_usage_observation_fact}

  defp provider(provider) when is_map(provider) do
    ProviderContext.new(
      name: Map.get(provider, "name"),
      integration_id: Map.get(provider, "integration_id"),
      model: Map.get(provider, "model"),
      voice: Map.get(provider, "voice"),
      request_id: Map.get(provider, "request_id"),
      operation_id: Map.get(provider, "operation_id"),
      session_id: Map.get(provider, "session_id")
    )
  end

  defp provider(_provider), do: {:error, :invalid_provider_context}

  defp attribution(attribution) when is_map(attribution) do
    Attribution.new(
      room_id: Map.get(attribution, "room_id"),
      incarnation_id: Map.get(attribution, "incarnation_id"),
      participant_id: Map.get(attribution, "participant_id"),
      activation_id: Map.get(attribution, "activation_id"),
      service_interval_id: Map.get(attribution, "service_interval_id"),
      leg_id: Map.get(attribution, "leg_id"),
      turn_id: Map.get(attribution, "turn_id"),
      utterance_id: Map.get(attribution, "utterance_id"),
      tool_call_id: Map.get(attribution, "tool_call_id")
    )
  end

  defp attribution(_attribution), do: {:error, :invalid_attribution}

  defp matching_envelope(attribution, fact) do
    if attribution.room_id == fact.room_id and
         attribution.incarnation_id == fact.incarnation_id and
         attribution.participant_id == fact.participant_id and
         attribution.activation_id == fact.activation_id and
         attribution.turn_id == fact.correlation_id and
         attribution.tool_call_id == fact.tool_call_id do
      :ok
    else
      {:error, :usage_attribution_mismatch}
    end
  end

  defp measurement(nil), do: {:ok, nil}

  defp measurement(measurement) when is_map(measurement) do
    with {:ok, unit} <- unit(Map.get(measurement, "unit")),
         {:ok, mode} <- mode(Map.get(measurement, "mode")),
         {:ok, status} <- status(Map.get(measurement, "status")),
         {:ok, provenance} <- provenance(Map.get(measurement, "provenance")) do
      Measurement.new(
        component: Map.get(measurement, "component"),
        unit: unit,
        quantity: Map.get(measurement, "quantity"),
        mode: mode,
        status: status,
        provenance: provenance,
        included_in: Map.get(measurement, "included_in")
      )
    end
  end

  defp measurement(_measurement), do: {:error, :invalid_measurement}

  defp capability("model_inference"), do: {:ok, :model_inference}
  defp capability("speech_to_text"), do: {:ok, :speech_to_text}
  defp capability("text_to_speech"), do: {:ok, :text_to_speech}
  defp capability("tool"), do: {:ok, :tool}
  defp capability("telephony"), do: {:ok, :telephony}
  defp capability(_capability), do: {:error, :invalid_capability}

  defp outcome("in_progress"), do: {:ok, :in_progress}
  defp outcome("succeeded"), do: {:ok, :succeeded}
  defp outcome("failed"), do: {:ok, :failed}
  defp outcome("cancelled"), do: {:ok, :cancelled}
  defp outcome("unknown"), do: {:ok, :unknown}
  defp outcome(_outcome), do: {:error, :invalid_outcome}

  defp unit("tokens"), do: {:ok, :tokens}
  defp unit("characters"), do: {:ok, :characters}
  defp unit("milliseconds"), do: {:ok, :milliseconds}
  defp unit("requests"), do: {:ok, :requests}
  defp unit(%{"currency" => currency}) when is_binary(currency), do: {:ok, {:currency, currency}}
  defp unit(_unit), do: {:error, :invalid_unit}

  defp mode("delta"), do: {:ok, :delta}
  defp mode("cumulative"), do: {:ok, :cumulative}
  defp mode(_mode), do: {:error, :invalid_mode}

  defp status("estimate"), do: {:ok, :estimate}
  defp status("final"), do: {:ok, :final}
  defp status("correction"), do: {:ok, :correction}
  defp status(_status), do: {:error, :invalid_status}

  defp provenance("provider_reported"), do: {:ok, :provider_reported}
  defp provenance("locally_measured"), do: {:ok, :locally_measured}
  defp provenance("library_estimate"), do: {:ok, :library_estimate}
  defp provenance("billing_lookup"), do: {:ok, :billing_lookup}
  defp provenance(_provenance), do: {:error, :invalid_provenance}
end
