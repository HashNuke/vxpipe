defmodule Vxpipe.Persistence.UsageValueCodec do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, ProviderContext}

  @spec encode_provider(ProviderContext.t()) :: map()
  def encode_provider(%ProviderContext{} = provider) do
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

  @spec decode_provider(map()) :: {:ok, ProviderContext.t()} | {:error, :invalid_provider_context}
  def decode_provider(provider) when is_map(provider) do
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

  def decode_provider(_provider), do: {:error, :invalid_provider_context}

  @spec encode_attribution(Attribution.t()) :: map()
  def encode_attribution(%Attribution{} = attribution) do
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

  @spec decode_attribution(map()) :: {:ok, Attribution.t()} | {:error, :invalid_attribution}
  def decode_attribution(attribution) when is_map(attribution) do
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

  def decode_attribution(_attribution), do: {:error, :invalid_attribution}

  @spec encode_measurement(Measurement.t() | nil) :: map() | nil
  def encode_measurement(nil), do: nil

  def encode_measurement(%Measurement{} = measurement) do
    compact(%{
      "component" => measurement.component,
      "unit" => encode_unit(measurement.unit),
      "quantity" => encode_quantity(measurement.quantity),
      "mode" => Atom.to_string(measurement.mode),
      "status" => Atom.to_string(measurement.status),
      "provenance" => Atom.to_string(measurement.provenance),
      "included_in" => measurement.included_in
    })
  end

  @spec decode_measurement(map() | nil) :: {:ok, Measurement.t() | nil} | {:error, term()}
  def decode_measurement(nil), do: {:ok, nil}

  def decode_measurement(measurement) when is_map(measurement) do
    with {:ok, unit} <- decode_unit(Map.get(measurement, "unit")),
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

  def decode_measurement(_measurement), do: {:error, :invalid_measurement}

  @spec encode_amount_unit(Measurement.unit()) :: {atom(), String.t() | nil}
  def encode_amount_unit({:currency, currency}), do: {:currency, currency}

  def encode_amount_unit(unit) when unit in [:tokens, :characters, :milliseconds, :requests],
    do: {unit, nil}

  @spec decode_amount_unit(atom(), String.t() | nil) ::
          {:ok, Measurement.unit()} | {:error, :invalid_unit}
  def decode_amount_unit(:currency, currency) when is_binary(currency),
    do: {:ok, {:currency, currency}}

  def decode_amount_unit(unit, nil) when unit in [:tokens, :characters, :milliseconds, :requests],
    do: {:ok, unit}

  def decode_amount_unit(_unit, _currency), do: {:error, :invalid_unit}

  @spec mode(String.t() | atom()) :: {:ok, Measurement.mode()} | {:error, :invalid_mode}
  def mode(value) when value in ["delta", :delta], do: {:ok, :delta}
  def mode(value) when value in ["cumulative", :cumulative], do: {:ok, :cumulative}
  def mode(_mode), do: {:error, :invalid_mode}

  @spec status(String.t() | atom()) :: {:ok, Measurement.status()} | {:error, :invalid_status}
  def status(value) when value in ["estimate", :estimate], do: {:ok, :estimate}
  def status(value) when value in ["final", :final], do: {:ok, :final}
  def status(value) when value in ["correction", :correction], do: {:ok, :correction}
  def status(_status), do: {:error, :invalid_status}

  @spec provenance(String.t() | atom()) ::
          {:ok, Measurement.provenance()} | {:error, :invalid_provenance}
  def provenance(value) when value in ["provider_reported", :provider_reported],
    do: {:ok, :provider_reported}

  def provenance(value) when value in ["locally_measured", :locally_measured],
    do: {:ok, :locally_measured}

  def provenance(value) when value in ["library_estimate", :library_estimate],
    do: {:ok, :library_estimate}

  def provenance(value) when value in ["billing_lookup", :billing_lookup],
    do: {:ok, :billing_lookup}

  def provenance(_provenance), do: {:error, :invalid_provenance}

  @spec capability(String.t() | atom()) ::
          {:ok, Vxpipe.CallEngine.Usage.Observation.capability()} | {:error, :invalid_capability}
  def capability(value) when value in ["model_inference", :model_inference],
    do: {:ok, :model_inference}

  def capability(value) when value in ["speech_to_text", :speech_to_text],
    do: {:ok, :speech_to_text}

  def capability(value) when value in ["text_to_speech", :text_to_speech],
    do: {:ok, :text_to_speech}

  def capability(value) when value in ["tool", :tool], do: {:ok, :tool}
  def capability(value) when value in ["telephony", :telephony], do: {:ok, :telephony}
  def capability(_capability), do: {:error, :invalid_capability}

  @spec outcome(String.t() | atom()) ::
          {:ok, Vxpipe.CallEngine.Usage.Observation.outcome()} | {:error, :invalid_outcome}
  def outcome(value) when value in ["in_progress", :in_progress], do: {:ok, :in_progress}
  def outcome(value) when value in ["succeeded", :succeeded], do: {:ok, :succeeded}
  def outcome(value) when value in ["failed", :failed], do: {:ok, :failed}
  def outcome(value) when value in ["cancelled", :cancelled], do: {:ok, :cancelled}
  def outcome(value) when value in ["unknown", :unknown], do: {:ok, :unknown}
  def outcome(_outcome), do: {:error, :invalid_outcome}

  defp encode_unit({:currency, currency}), do: %{"currency" => currency}
  defp encode_unit(unit), do: Atom.to_string(unit)

  defp decode_unit("tokens"), do: {:ok, :tokens}
  defp decode_unit("characters"), do: {:ok, :characters}
  defp decode_unit("milliseconds"), do: {:ok, :milliseconds}
  defp decode_unit("requests"), do: {:ok, :requests}
  defp decode_unit(%{"currency" => currency}) when is_binary(currency),
    do: {:ok, {:currency, currency}}

  defp decode_unit(_unit), do: {:error, :invalid_unit}

  defp encode_quantity(%Decimal{} = quantity), do: Decimal.to_string(quantity, :normal)
  defp encode_quantity(quantity), do: quantity

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
