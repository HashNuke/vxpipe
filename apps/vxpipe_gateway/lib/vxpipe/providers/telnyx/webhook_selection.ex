defmodule Vxpipe.Providers.Telnyx.WebhookSelection do
  @moduledoc false

  alias Vxpipe.Calls.{ProviderAuth, ProviderCredential, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, WebhookService}
  alias Vxpipe.Providers.Telnyx.WebhookVerifier

  @derive {Inspect, only: [:scope, :owner]}
  defstruct [:scope, :owner, :service, :registry, :credential, :verifier_options]

  def select(registry, {:scope, scope}, body) do
    with :ok <- ProviderAuth.owner(scope) do
      case WebhookService.scoped_telnyx_owner(scope, body) do
        {:ok, service, owner} -> retained(service, owner)
        :not_found -> fresh(registry, scope)
        {:error, _reason} = error -> error
      end
    else
      _invalid -> {:error, :service_not_found}
    end
  rescue
    _error -> {:error, :webhook_processing_unavailable}
  catch
    :exit, _reason -> {:error, :webhook_processing_unavailable}
  end

  def resolve(%__MODULE__{service: %ConfiguredService{} = service, owner: owner}, _webhook),
    do: {:ok, service, owner}

  def resolve(%__MODULE__{} = selection, webhook) do
    with {:ok, application} <- application_id(webhook.body),
         {:ok, candidate} <-
           TelephonyServices.fetch_telnyx_application(
             application,
             selection.registry.repository_options
           ),
         :ok <- matching_tenant(selection.scope, candidate.tenant_key),
         {:ok, snapshot} <-
           TelephonyServices.resolve(
             candidate.tenant_key,
             candidate.name,
             selection.registry.repository_options
           ),
         :ok <- matching_selection(selection, candidate, snapshot),
         {:ok, service} <-
           ConfiguredService.from_snapshot(
             snapshot,
             selection.registry.public_base_url,
             selection.registry.adapters
           ),
         :ok <- WebhookVerifier.verify(webhook, service.verifier_options) do
      {:ok, service, nil}
    else
      {:error, :telephony_service_not_found} ->
        {:error, :service_not_found}

      {:error, reason}
      when reason in [
             :invalid_telnyx_webhook,
             :webhook_source_mismatch,
             :invalid_webhook_authentication
           ] ->
        {:error, reason}

      _unavailable ->
        {:error, :webhook_processing_unavailable}
    end
  rescue
    _error -> {:error, :webhook_processing_unavailable}
  catch
    :exit, _reason -> {:error, :webhook_processing_unavailable}
  end

  defp retained(service, owner),
    do:
      {:ok,
       %__MODULE__{
         service: service,
         owner: owner,
         verifier_options: service.verifier_options
       }}

  defp fresh(registry, scope) do
    with {:ok, selected} <-
           ProviderCredentials.resolve(scope, "telnyx", "telnyx", registry.repository_options),
         credential = selected.credential,
         true <-
           ProviderCredential.owner(credential) == scope and credential.provider == "telnyx" and
             credential.name == "telnyx" and credential.status == :active,
         :ok <- ProviderAuth.validate("telnyx", credential.auth_kind, selected.payload),
         public_key = Map.get(selected.payload, "public_key"),
         true <- Vxpipe.Providers.Telnyx.Credential.public_key?(public_key) do
      {:ok,
       %__MODULE__{
         scope: scope,
         registry: registry,
         credential: {credential.id, credential.version},
         verifier_options: [public_key: public_key]
       }}
    else
      {:error, reason} when reason in [:provider_credential_unavailable, :tenant_not_found] ->
        {:error, :service_not_found}

      false ->
        {:error, :service_not_found}

      {:error, :invalid_provider_auth} ->
        {:error, :service_not_found}

      _unavailable ->
        {:error, :webhook_processing_unavailable}
    end
  end

  defp matching_tenant(:platform, _tenant), do: :ok
  defp matching_tenant({:tenant, tenant}, tenant), do: :ok
  defp matching_tenant(_scope, _tenant), do: {:error, :webhook_source_mismatch}

  defp matching_selection(selection, candidate, snapshot) do
    service = snapshot.service
    credential = snapshot.credential.credential

    if service.id == candidate.id and
         service.provider_connection_id == candidate.provider_connection_id and
         service.credential_name == "telnyx" and service.credential_owner == selection.scope and
         {credential.id, credential.version} == selection.credential,
       do: :ok,
       else: {:error, :webhook_source_mismatch}
  end

  defp application_id(body) do
    case JSON.decode(body) do
      {:ok, %{"data" => %{"payload" => %{"connection_id" => application}}}}
      when is_binary(application) and byte_size(application) in 1..128 ->
        {:ok, application}

      _invalid ->
        {:error, :invalid_telnyx_webhook}
    end
  end
end
