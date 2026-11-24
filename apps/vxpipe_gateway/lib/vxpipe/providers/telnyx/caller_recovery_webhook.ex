defmodule Vxpipe.Providers.Telnyx.CallerRecoveryWebhook do
  @moduledoc "Matches terminal evidence after the carrier owner exits, without recreating that owner."

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{ProviderCredential, ProviderCredentials}

  def select(scope, event, options) do
    with {:ok, claim, command_id, deadline} <- Calls.find_caller_recovery(scope, event, options),
         true <- scope in [:platform, {:tenant, claim.call.tenant_key}],
         %{telephony_service: reference} <-
           Map.fetch!(claim.call.plan.participants, claim.participant_ref),
         true <-
           reference.service_id == claim.service_id and
             reference.provider_connection_id == event.provider_connection_id and
             reference.provider == "telnyx" and reference.tenant_id == claim.call.tenant_key,
         {:ok, credential} <-
           ProviderCredentials.resolve(
             reference.credential_owner,
             "telnyx",
             reference.credential_name,
             options
           ),
         true <-
           credential.credential.status == :active and
             credential.credential.id == reference.credential_id and
             ProviderCredential.owner(credential.credential) == reference.credential_owner do
      {:ok,
       %{
         recovery_claim: claim,
         command_id: command_id,
         deadline: deadline,
         options: options,
         verifier_options: [public_key: credential.payload["public_key"]]
       }}
    else
      {:error, :not_found} -> {:error, :service_not_found}
      _unavailable -> {:error, :webhook_processing_unavailable}
    end
  end

  def store(selection) do
    case Calls.record_caller_recovery(
           selection.recovery_claim,
           :carrier_ended,
           selection.command_id,
           selection.deadline,
           selection.options
         ) do
      :ok -> :ok
      _unavailable -> {:error, :webhook_processing_unavailable}
    end
  end
end
