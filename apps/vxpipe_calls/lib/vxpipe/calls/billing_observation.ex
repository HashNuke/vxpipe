defmodule Vxpipe.Calls.BillingObservation do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.Observation
  alias Vxpipe.Calls.{BillingLookupRequest, BillingLookupResult}

  @spec build(BillingLookupRequest.t(), BillingLookupResult.t()) ::
          {:ok, Observation.t()} | {:error, :invalid_billing_observation}
  def build(%BillingLookupRequest{} = request, %BillingLookupResult{} = result) do
    options = [
      id: observation_id(request, result),
      delivery_id: result.delivery_id,
      source_sequence: result.source_sequence,
      tenant_id: request.tenant_key,
      call_id: request.call_id,
      attempt_id: request.attempt_id,
      capability: request.capability,
      provider: request.provider,
      attribution: request.attribution,
      measurement: result.measurement,
      outcome: request.outcome,
      observed_at: result.observed_at
    ]

    case Observation.new(options) do
      {:ok, observation} -> {:ok, observation}
      {:error, :invalid_observation} -> {:error, :invalid_billing_observation}
    end
  end

  def build(_request, _result), do: {:error, :invalid_billing_observation}

  defp observation_id(request, result) do
    digest =
      :erlang.term_to_binary({
        request.tenant_key,
        request.call_id,
        request.attempt_id,
        request.capability,
        request.provider,
        request.attribution,
        result.delivery_id,
        result.source_sequence,
        result.measurement
      })
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "uobs_" <> digest
  end
end
