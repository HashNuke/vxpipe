defmodule Vxpipe.Persistence.UsageAmountRecord do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{EffectiveAmount, Measurement}
  alias Vxpipe.Persistence.UsageValueCodec

  @spec attributes(pos_integer(), EffectiveAmount.t()) :: map()
  def attributes(call_id, %EffectiveAmount{} = amount) do
    {unit, currency} = UsageValueCodec.encode_amount_unit(amount.unit)

    %{
      public_id: public_id(amount),
      call_id: call_id,
      attempt_id: amount.attempt_id,
      capability: amount.capability,
      provider: UsageValueCodec.encode_provider(amount.provider),
      attribution: UsageValueCodec.encode_attribution(amount.attribution),
      component: amount.component,
      unit: unit,
      currency: currency,
      quantity: amount.quantity,
      mode: amount.mode,
      status: amount.status,
      provenance: amount.provenance,
      included_in: amount.included_in,
      observation_ids: amount.observation_ids
    }
  end

  @spec decode(struct()) :: {:ok, EffectiveAmount.t()} | {:error, :invalid_usage_amount}
  def decode(stored) do
    with {:ok, capability} <- UsageValueCodec.capability(stored.capability),
         {:ok, provider} <- UsageValueCodec.decode_provider(stored.provider),
         {:ok, attribution} <- UsageValueCodec.decode_attribution(stored.attribution),
         {:ok, unit} <- UsageValueCodec.decode_amount_unit(stored.unit, stored.currency),
         {:ok, mode} <- UsageValueCodec.mode(stored.mode),
         {:ok, status} <- UsageValueCodec.status(stored.status),
         {:ok, provenance} <- UsageValueCodec.provenance(stored.provenance),
         {:ok, measurement} <- measurement(stored, unit, mode, status, provenance),
         true <- valid_observation_ids?(stored.observation_ids) do
      {:ok,
       %EffectiveAmount{
         attempt_id: stored.attempt_id,
         capability: capability,
         provider: provider,
         attribution: attribution,
         component: measurement.component,
         unit: measurement.unit,
         quantity: measurement.quantity,
         mode: measurement.mode,
         status: measurement.status,
         provenance: measurement.provenance,
         included_in: measurement.included_in,
         observation_ids: stored.observation_ids
       }}
    else
      _invalid -> {:error, :invalid_usage_amount}
    end
  end

  defp measurement(stored, unit, mode, status, provenance) do
    Measurement.new(
      component: stored.component,
      unit: unit,
      quantity: quantity(unit, stored.quantity),
      mode: mode,
      status: status,
      provenance: provenance,
      included_in: stored.included_in
    )
  end

  defp quantity({:currency, _currency}, %Decimal{} = quantity), do: quantity

  defp quantity(unit, %Decimal{} = quantity)
       when unit in [:tokens, :characters, :milliseconds, :requests] do
    if Decimal.equal?(quantity, Decimal.round(quantity, 0)),
      do: Decimal.to_integer(quantity),
      else: :invalid_scalar_quantity
  end

  defp quantity(_unit, _quantity), do: :invalid_quantity

  defp valid_observation_ids?([first | rest]) do
    Enum.all?([first | rest], &(is_binary(&1) and &1 != "" and byte_size(&1) <= 128))
  end

  defp valid_observation_ids?(_observation_ids), do: false

  defp public_id(amount) do
    identity = {
      amount.attempt_id,
      amount.capability,
      amount.provider,
      amount.attribution,
      amount.component,
      amount.unit,
      amount.provenance,
      amount.included_in
    }

    digest = :crypto.hash(:sha256, :erlang.term_to_binary(identity, [:deterministic]))
    "uamt_" <> Base.encode16(digest, case: :lower)
  end
end
