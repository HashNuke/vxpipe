defmodule Vxpipe.Calls.ProviderCredentials do
  @moduledoc "Trusted provider provisioning and private resolution. Not a tenant-facing authorization boundary."

  alias Vxpipe.Calls.{ProviderAuth, ProviderCredential, PublicId, Repositories}

  def provision(tenant_key, provider, name, auth_kind, payload, options \\ []) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, name),
         :ok <- ProviderAuth.validate(provider, auth_kind, payload),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      credential = %ProviderCredential{
        id: PublicId.uuid(),
        tenant_key: tenant_key,
        provider: provider,
        name: name,
        auth_kind: auth_kind
      }

      Repositories.call(repository, :provision, [credential, payload])
    end
  end

  def list(tenant_key, options \\ []) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      Repositories.call(repository, :list, [tenant_key])
    end
  end

  def resolve(tenant_key, provider, name \\ "default", options \\ []) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, name),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      Repositories.call(repository, :resolve, [tenant_key, provider, name])
    end
  end
end
