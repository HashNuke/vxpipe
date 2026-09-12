defmodule Vxpipe.Persistence.UsageObservationRecord do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.Observation
  alias Vxpipe.Persistence.UsageValueCodec

  @spec attributes(pos_integer(), Observation.t()) :: map()
  def attributes(call_id, %Observation{} = observation) do
    %{
      public_id: observation.id,
      call_id: call_id,
      attempt_id: observation.attempt_id,
      capability: observation.capability,
      delivery_id: observation.delivery_id,
      source_sequence: observation.source_sequence,
      provider: UsageValueCodec.encode_provider(observation.provider),
      attribution: UsageValueCodec.encode_attribution(observation.attribution),
      measurement: UsageValueCodec.encode_measurement(observation.measurement),
      outcome: observation.outcome,
      observed_at: observation.observed_at
    }
  end

  @spec decode(struct(), String.t(), String.t()) ::
          {:ok, Observation.t()} | {:error, :invalid_usage_observation}
  def decode(stored, tenant_key, call_id) do
    with {:ok, capability} <- UsageValueCodec.capability(stored.capability),
         {:ok, provider} <- UsageValueCodec.decode_provider(stored.provider),
         {:ok, attribution} <- UsageValueCodec.decode_attribution(stored.attribution),
         {:ok, measurement} <- UsageValueCodec.decode_measurement(stored.measurement),
         {:ok, outcome} <- UsageValueCodec.outcome(stored.outcome),
         {:ok, observation} <-
           Observation.new(
             id: stored.public_id,
             tenant_id: tenant_key,
             call_id: call_id,
             attempt_id: stored.attempt_id,
             capability: capability,
             delivery_id: stored.delivery_id,
             source_sequence: stored.source_sequence,
             provider: provider,
             attribution: attribution,
             measurement: measurement,
             outcome: outcome,
             observed_at: stored.observed_at
           ) do
      {:ok, observation}
    else
      _invalid -> {:error, :invalid_usage_observation}
    end
  end
end
