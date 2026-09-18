defmodule Vxpipe.Calls.ProviderCredentials do
  @moduledoc "Trusted provider provisioning and private resolution. Not a tenant-facing authorization boundary."

  alias Vxpipe.Calls.{
    ProviderAuth,
    ProviderCredential,
    ProviderCredentialHints,
    PublicId,
    Repositories
  }

  def provision(tenant_key, provider, name, auth_kind, payload, options \\ []) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, name),
         :ok <- ProviderAuth.validate(provider, auth_kind, payload),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      credential = %ProviderCredential{
        id: PublicId.uuid(),
        tenant_key: tenant_key,
        provider: provider,
        name: name,
        auth_kind: auth_kind,
        secret_hints: ProviderCredentialHints.from_payload(auth_kind, payload)
      }

      Repositories.call(repository, :provision, [credential, payload])
    end
  end

  def replace(tenant_key, credential_id, provider, auth_kind, payload, options \\ []) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, provider),
         :ok <- credential_id(credential_id),
         :ok <- ProviderAuth.validate(provider, auth_kind, payload),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      Repositories.call(repository, :replace, [
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        ProviderCredentialHints.from_payload(auth_kind, payload)
      ])
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

  defp credential_id(value) when is_binary(value) and byte_size(value) in 1..128, do: :ok
  defp credential_id(_value), do: {:error, :invalid_provider_credential_id}
end
