defmodule Vxpipe.Providers.Telnyx.WebhookSelection do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Calls.{ProviderAuth, ProviderCredential, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, ServiceRegistry, WebhookService}
  alias Vxpipe.Providers.Telnyx.{WebhookDecoder, WebhookVerifier}

  @derive {Inspect, only: [:scope, :owner]}
  defstruct [
    :scope,
    :owner,
    :service,
    :registry,
    :credential,
    :verifier_options,
    :candidate,
    :application
  ]

  def select(registry, {:scope, scope}, body) do
    with :ok <- ProviderAuth.owner(scope) do
      case WebhookService.scoped_telnyx_owner(scope, body) do
        {:ok, service, owner} -> retained(service, owner)
        :not_found -> fresh(registry, scope, body)
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
    candidate = selection.candidate

    with {:ok, snapshot} <-
           TelephonyServices.resolve(
             candidate.tenant_key,
             candidate.name,
             selection.registry.repository_options
           ),
         :ok <- matching_selection(selection, snapshot),
         {:ok, service} <- ServiceRegistry.configure(selection.registry, snapshot),
         :ok <- WebhookVerifier.verify(webhook, service.verifier_options) do
      {:ok, service, nil}
    else
      {:error, reason}
      when reason in [:webhook_source_mismatch, :invalid_webhook_authentication] ->
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
       %__MODULE__{service: service, owner: owner, verifier_options: service.verifier_options}}

  # Unsigned fields locate one candidate. Only a verified raw body can reach resolve/2
  # and dispatch; a tenant URL cannot select another tenant's credential.
  defp fresh(registry, scope, body) do
    with {:ok, event} <- incoming_event(body),
         {:ok, candidate} <-
           TelephonyServices.fetch_telnyx_route(
             scope,
             event.provider_connection_id,
             event.to,
             registry.repository_options
           ),
         true <- scope == :platform or scope == {:tenant, candidate.tenant_key},
         {:ok, selected} <-
           ProviderCredentials.resolve(
             candidate.tenant_key,
             "telnyx",
             "telnyx",
             registry.repository_options
           ),
         credential = selected.credential,
         true <-
           ProviderCredential.available_to?(credential, candidate.tenant_key) and
             credential.provider == "telnyx" and credential.name == "telnyx" and
             credential.status == :active,
         :ok <- ProviderAuth.validate("telnyx", credential.auth_kind, selected.payload),
         public_key = Map.get(selected.payload, "public_key"),
         true <- Vxpipe.Providers.Telnyx.Credential.public_key?(public_key) do
      {:ok,
       %__MODULE__{
         scope: scope,
         registry: registry,
         candidate: candidate,
         application: event.provider_connection_id,
         credential: {credential.id, credential.version},
         verifier_options: [public_key: public_key]
       }}
    else
      {:error, :invalid_telnyx_webhook} = error ->
        error

      {:error, reason}
      when reason in [
             :telephony_service_not_found,
             :provider_credential_unavailable,
             :provider_credential_not_found,
             :tenant_not_found,
             :service_not_found,
             :invalid_provider_auth
           ] ->
        {:error, :service_not_found}

      false ->
        {:error, :service_not_found}

      _unavailable ->
        {:error, :webhook_processing_unavailable}
    end
  end

  defp matching_selection(selection, snapshot) do
    candidate = selection.candidate
    service = snapshot.service
    credential = snapshot.credential.credential

    if service.id == candidate.id and service.tenant_key == candidate.tenant_key and
         service.name == candidate.name and
         service.provider_connection_id == selection.application and
         service.credential_name == "telnyx" and
         {credential.id, credential.version} == selection.credential,
       do: :ok,
       else: {:error, :webhook_source_mismatch}
  end

  defp incoming_event(body) do
    case WebhookDecoder.decode(%Webhook{body: body, headers: %{}, received_at: 0}) do
      {:ok, %Event{kind: :incoming} = event} -> {:ok, event}
      {:error, _reason} = error -> error
      _not_a_new_call -> {:error, :service_not_found}
    end
  end
end
