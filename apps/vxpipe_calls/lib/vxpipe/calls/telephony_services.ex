defmodule Vxpipe.Calls.TelephonyServices do
  @moduledoc """
  Trusted tenant service registration, metadata lookup and private authentication resolution.

  These functions are host operations, not a tenant-facing authorization boundary.
  An ingress locator retrieves candidate metadata; it does not authenticate a webhook.
  Fetching metadata does not resolve or authorize the use of a private credential.
  """

  alias Vxpipe.Calls.{ProviderAuth, Repositories, ResolvedTelephonyService, TelephonyService}

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

  defp validate_snapshot(snapshot, tenant_key, name) do
    service = snapshot.service
    credential = snapshot.credential.credential

    with :ok <- TelephonyService.validate(service),
         true <- service.tenant_key == tenant_key and service.name == name,
         true <- credential.id == service.credential_id and credential.tenant_key == tenant_key,
         true <- credential.provider == service.provider and credential.status == :active,
         :ok <-
           ProviderAuth.validate(
             credential.provider,
             credential.auth_kind,
             snapshot.credential.payload
           ) do
      :ok
    else
      _invalid -> {:error, :provider_credential_unavailable}
    end
  end
end
