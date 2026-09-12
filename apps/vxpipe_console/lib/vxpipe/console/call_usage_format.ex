defmodule Vxpipe.Console.CallUsageFormat do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Attribution, EffectiveAmount, ProviderContext}
  alias Vxpipe.Calls.UsageTotal

  @spec capability(atom()) :: String.t()
  def capability(:model_inference), do: "Model inference"
  def capability(:speech_to_text), do: "Speech to text"
  def capability(:text_to_speech), do: "Text to speech"
  def capability(:tool), do: "Tool"
  def capability(:telephony), do: "Telephony"

  @spec provenance(atom()) :: String.t()
  def provenance(:provider_reported), do: "Provider reported"
  def provenance(:locally_measured), do: "Locally measured"
  def provenance(:library_estimate), do: "Library estimate"
  def provenance(:billing_lookup), do: "Billing lookup"

  @spec quantity(EffectiveAmount.t() | UsageTotal.t()) :: String.t()
  def quantity(%{quantity: quantity, unit: {:currency, currency}}) do
    Decimal.to_string(quantity, :normal) <> " " <> currency
  end

  def quantity(%{quantity: quantity, unit: unit}) when is_integer(quantity) do
    Integer.to_string(quantity) <> " " <> unit_label(unit, quantity)
  end

  @spec provider(ProviderContext.t()) :: String.t()
  def provider(%ProviderContext{} = provider) do
    [provider.name, provider.integration_id, provider.model, provider.voice]
    |> present_values()
    |> Enum.join(" · ")
  end

  @spec provider(UsageTotal.t()) :: String.t()
  def provider(%UsageTotal{} = total) do
    [total.provider_name, total.integration_id, total.model, total.voice]
    |> present_values()
    |> Enum.join(" · ")
  end

  @spec attribution(Attribution.t() | UsageTotal.t()) :: String.t()
  def attribution(%Attribution{} = attribution) do
    [
      pair("participant", attribution.participant_id),
      pair("activation", attribution.activation_id),
      pair("interval", attribution.service_interval_id),
      pair("leg", attribution.leg_id),
      pair("turn", attribution.turn_id),
      pair("utterance", attribution.utterance_id),
      pair("tool", attribution.tool_call_id)
    ]
    |> attribution_label()
  end

  def attribution(%UsageTotal{} = total) do
    [
      pair("participant", total.participant_id),
      pair("activation", total.activation_id),
      pair("interval", total.service_interval_id),
      pair("leg", total.leg_id),
      pair("turn", total.turn_id),
      pair("utterance", total.utterance_id),
      pair("tool", total.tool_call_id)
    ]
    |> attribution_label()
  end

  @spec provider_references(ProviderContext.t()) :: String.t()
  def provider_references(%ProviderContext{} = provider) do
    [
      pair("request", provider.request_id),
      pair("operation", provider.operation_id),
      pair("session", provider.session_id)
    ]
    |> present_values()
    |> case do
      [] -> "No external reference"
      references -> Enum.join(references, " · ")
    end
  end

  @spec settlement(EffectiveAmount.t()) :: String.t()
  def settlement(%EffectiveAmount{} = amount) do
    [mode(amount.mode), status(amount.status), provenance(amount.provenance)]
    |> Enum.join(" · ")
  end

  @spec component(EffectiveAmount.t()) :: String.t()
  def component(%EffectiveAmount{included_in: nil} = amount), do: amount.component

  def component(%EffectiveAmount{} = amount) do
    amount.component <> " · included in " <> amount.included_in
  end

  defp unit_label(:tokens, 1), do: "token"
  defp unit_label(:tokens, _quantity), do: "tokens"
  defp unit_label(:characters, 1), do: "character"
  defp unit_label(:characters, _quantity), do: "characters"
  defp unit_label(:milliseconds, 1), do: "millisecond"
  defp unit_label(:milliseconds, _quantity), do: "milliseconds"
  defp unit_label(:requests, 1), do: "request"
  defp unit_label(:requests, _quantity), do: "requests"

  defp mode(:delta), do: "Delta"
  defp mode(:cumulative), do: "Cumulative"

  defp status(:estimate), do: "Estimate"
  defp status(:final), do: "Final"
  defp status(:correction), do: "Correction"

  defp pair(_label, nil), do: nil
  defp pair(label, value), do: label <> " " <> value

  defp attribution_label(values) do
    values
    |> present_values()
    |> case do
      [] -> "Call-wide"
      dimensions -> Enum.join(dimensions, " · ")
    end
  end

  defp present_values(values), do: Enum.reject(values, &is_nil/1)
end
