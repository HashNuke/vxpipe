defmodule Vxpipe.Calls.TelephonyServices do
  @moduledoc """
  Trusted tenant service registration and metadata lookup.

  These functions are host operations, not a tenant-facing authorization boundary.
  An ingress locator retrieves candidate metadata; it does not authenticate a webhook.
  Fetching metadata does not resolve or authorize the use of a private credential.
  """

  alias Vxpipe.Calls.{ProviderAuth, Repositories, TelephonyService}

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
end
