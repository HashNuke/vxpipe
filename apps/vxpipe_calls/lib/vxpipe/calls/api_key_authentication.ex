defmodule Vxpipe.Calls.ApiKeyAuthentication do
  @moduledoc "Authenticates a stored API key before a request has selected a tenant."

  alias Vxpipe.Calls.{ApiKeyManagement, InstallationOperator, Principal, Repositories}

  @spec authenticate(term(), keyword()) ::
          {:ok, Principal.t() | InstallationOperator.t()} | {:error, term()}
  def authenticate(secret, options \\ [])

  def authenticate("vxop_" <> _secret, _options), do: {:error, :invalid_api_key}

  def authenticate("vxpk_" <> _secret = secret, options),
    do: ApiKeyManagement.authenticate_platform(secret, options)

  def authenticate(secret, options) when is_binary(secret) and byte_size(secret) in 1..256 do
    with {:ok, repository} <- Repositories.fetch(options, :credential_repository),
         {:ok, record} <-
           Repositories.call(repository, :fetch_api_key_by_digest, [:crypto.hash(:sha256, secret)]) do
      principal(record)
    else
      {:error, reason} when reason in [:not_found, :ambiguous_api_key] ->
        {:error, :invalid_api_key}

      {:error, _reason} = error ->
        error
    end
  end

  def authenticate(_secret, _options), do: {:error, :invalid_api_key}

  defp principal(%{revoked_at: nil} = record) do
    {:ok,
     %Principal{
       tenant_key: record.tenant_key,
       api_key_id: record.id,
       scopes: record.scopes
     }}
  end

  defp principal(_revoked), do: {:error, :invalid_api_key}
end
