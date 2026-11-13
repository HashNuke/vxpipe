defmodule Vxpipe.Providers.Telnyx.CallCostWebhook do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.Observation

  alias Vxpipe.Calls.{
    ProviderCredential,
    ProviderCredentials,
    PublicationTriggers,
    UsageProjections
  }

  def select(cost, {:scope, scope}, options) do
    with {:ok, {observation, reference}} <-
           UsageProjections.telephony_target("telnyx", cost.leg_id, cost.session_id, options),
         :ok <-
           scope(
             scope,
             observation.tenant_id,
             reference.provider_connection_id,
             cost.application_id
           ),
         {:ok, resolved} <-
           ProviderCredentials.resolve(
             reference.credential_owner,
             "telnyx",
             reference.credential_name,
             options
           ),
         true <-
           resolved.credential.id == reference.credential_id and
             resolved.credential.status == :active and
             ProviderCredential.owner(resolved.credential) == reference.credential_owner do
      {:ok,
       %{
         cost: cost,
         observation: observation,
         options: options,
         verifier_options: [public_key: resolved.payload["public_key"]]
       }}
    else
      {:error, :webhook_source_mismatch} = mismatch -> mismatch
      _unavailable -> {:error, :webhook_processing_unavailable}
    end
  rescue
    _exception -> {:error, :webhook_processing_unavailable}
  end

  def store(%{cost: cost, observation: source, options: options}) do
    result =
      Enum.reduce_while(cost.measurements, :ok, fn measurement, :ok ->
        component = if measurement, do: measurement.component, else: "receipt"

        id =
          :crypto.hash(
            :sha256,
            :erlang.term_to_binary(
              {"telnyx-cost", cost.application_id, cost.leg_id, cost.session_id, cost.id,
               component}
            )
          )
          |> Base.encode16(case: :lower)

        with {:ok, observation} <-
               Observation.new(
                 id: id,
                 delivery_id: cost.fingerprint,
                 tenant_id: source.tenant_id,
                 call_id: source.call_id,
                 attempt_id: source.attempt_id,
                 capability: :telephony,
                 provider: source.provider,
                 attribution: source.attribution,
                 measurement: measurement,
                 outcome: :unknown,
                 observed_at: cost.observed_at
               ),
             {:ok, _stored} <- UsageProjections.store(observation, options) do
          {:cont, :ok}
        else
          _unavailable -> {:halt, {:error, :webhook_processing_unavailable}}
        end
      end)

    if result == :ok do
      _result = PublicationTriggers.request(source.tenant_id, source.call_id, options)
    end

    result
  rescue
    _exception -> {:error, :webhook_processing_unavailable}
  end

  defp scope(scope, tenant, application, application)
       when scope == :platform or scope == {:tenant, tenant}, do: :ok

  defp scope(_scope, _tenant, _expected, _received), do: {:error, :webhook_source_mismatch}
end
