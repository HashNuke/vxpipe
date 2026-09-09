defmodule Vxpipe.Calls.CredentialRepository do
  @moduledoc "Persistence port for tenants and hash-only Vxpipe API keys."

  alias Vxpipe.Calls.Tenant

  @type context :: term()
  @type api_key_record :: %{
          id: String.t(),
          tenant_key: String.t(),
          name: String.t(),
          scopes: MapSet.t(:admin | :calls),
          digest: binary(),
          revoked_at: nil | DateTime.t(),
          inserted_at: DateTime.t()
        }

  @callback bootstrap_tenant(context(), Tenant.t(), api_key_record()) ::
              {:ok, {Tenant.t(), api_key_record()}} | {:error, term()}
  @callback fetch_tenant(context(), String.t()) :: {:ok, Tenant.t()} | {:error, :not_found}
  @callback insert_api_key(context(), String.t(), api_key_record()) ::
              {:ok, api_key_record()} | {:error, term()}
  @callback fetch_api_key(context(), String.t(), binary()) ::
              {:ok, api_key_record()} | {:error, :not_found}
  @callback revoke_api_key(context(), String.t(), String.t(), DateTime.t()) ::
              {:ok, api_key_record()} | {:error, :not_found}
end
