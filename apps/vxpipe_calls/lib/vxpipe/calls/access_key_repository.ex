defmodule Vxpipe.Calls.AccessKeyRepository do
  @moduledoc "Storage boundary for scoped access-key metadata and issuance."
  @callback list(term(), term(), boolean(), map()) :: {:ok, map()} | {:error, atom()}
  @callback tenants(term(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback insert(term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback fetch(term(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback revoke(term(), String.t(), DateTime.t()) :: :ok | {:error, atom()}
  @callback authenticate_platform(term(), binary()) :: {:ok, String.t()} | {:error, atom()}
end
