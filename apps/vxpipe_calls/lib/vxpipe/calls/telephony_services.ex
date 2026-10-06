defmodule Vxpipe.Calls.TelephonyServices do
  @moduledoc """
  Trusted tenant service registration, metadata lookup and private authentication resolution.

  These functions are host operations, not a tenant-facing authorization boundary.
  An ingress locator retrieves candidate metadata; it does not authenticate a webhook.
  Fetching metadata does not resolve or authorize the use of a private credential.
  """

  alias Vxpipe.Calls.{
    ProviderAuth,
    ProviderCredential,
    Repositories,
    ResolvedTelephonyService,
    TelephonyService
  }

  alias Vxpipe.CallEngine.Telephony.ServiceReference

  @doc "Projects stable, non-secret identity for a prepared plan or locked comparison."
  def reference(%TelephonyService{} = service) do
    %ServiceReference{
      tenant_id: service.tenant_key,
      service_id: service.id,
      name: service.name,
      provider: service.provider,
      provider_connection_id: service.provider_connection_id,
      credential_id: service.credential_id,
      credential_owner: service.credential_owner,
      credential_name: service.credential_name
    }
  end

  @doc """
  Checks a service's pinned identity and caller ID requirement under its repository lock.

  A changed or unbound identity is `:provider_credential_unavailable`; a dialing service
  without an outbound number is `:telephony_caller_id_missing`, so callers can say which.
  """
  @spec check_requirement(TelephonyService.t(), map()) ::
          :ok | {:error, :provider_credential_unavailable | :telephony_caller_id_missing}
  def check_requirement(%TelephonyService{} = service, requirement) do
    cond do
      not reference_matches?(service, requirement) -> {:error, :provider_credential_unavailable}
      caller_id_missing?(service, requirement) -> {:error, :telephony_caller_id_missing}
      true -> :ok
    end
  end

  def meets_requirement?(%TelephonyService{} = service, requirement),
    do: check_requirement(service, requirement) == :ok

  defp reference_matches?(service, requirement) do
    case Map.fetch(requirement, :reference) do
      {:ok, expected} -> reference(service) == expected
      :error -> true
    end
  end

  defp caller_id_missing?(service, requirement) do
    Map.get(requirement, :outbound_required?, false) and
      not (is_binary(service.outbound_number) and service.outbound_number != "")
  end

  def register(tenant_key, attributes, options \\ []) do
    with {:ok, service} <- TelephonyService.new(tenant_key, attributes),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :register, [service])
    end
  end

  def fetch(tenant_key, name, options \\ []) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- TelephonyService.identifier(name),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :fetch, [tenant_key, name])
    end
  end

  def fetch_by_ingress(ingress_key, options \\ []) do
    with :ok <- TelephonyService.identifier(ingress_key),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :fetch_by_ingress, [ingress_key])
    end
  end

  def fetch_telnyx_application(application_id, options \\ [])

  def fetch_telnyx_application(application_id, options)
      when is_binary(application_id) and byte_size(application_id) in 1..128 do
    with {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :fetch_telnyx_application, [application_id])
    end
  end

  def fetch_telnyx_application(_application_id, _options),
    do: {:error, :telephony_service_not_found}

  def resolve(tenant_key, name, options \\ []) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- TelephonyService.identifier(name),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository),
         {:ok, %ResolvedTelephonyService{} = snapshot} <-
           Repositories.call(repository, :resolve, [tenant_key, name]),
         :ok <- validate_snapshot(snapshot, tenant_key, name) do
      {:ok, snapshot}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  end

  def with_active(_tenant_key, [], _options, operation), do: operation.()

  def with_active(tenant_key, requirements, options, operation) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :with_active, [tenant_key, requirements, operation])
    end
  end

  defp credential_owner_matches?(%{credential_name: nil, tenant_key: tenant}, credential),
    do: ProviderCredential.owner(credential) == {:tenant, tenant}

  defp credential_owner_matches?(service, credential),
    do:
      ProviderCredential.available_to?(credential, service.tenant_key) and
        ProviderCredential.owner(credential) == service.credential_owner and
        credential.name == service.credential_name

  defp validate_snapshot(snapshot, tenant_key, name) do
    service = snapshot.service
    credential = snapshot.credential.credential

    with :ok <- TelephonyService.validate(service),
         true <- service.tenant_key == tenant_key and service.name == name,
         true <-
           credential.id == service.credential_id and
             credential_owner_matches?(service, credential),
         true <- credential.provider == service.provider and credential.status == :active,
         :ok <-
           ProviderAuth.validate(
             credential.provider,
             credential.auth_kind,
             snapshot.credential.payload
           ),
         true <- TelephonyService.credential_matches?(service, snapshot.credential.payload) do
      :ok
    else
      _invalid -> {:error, :provider_credential_unavailable}
    end
  end
end
