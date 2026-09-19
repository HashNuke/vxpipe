defmodule Vxpipe.Calls.OperatorApiKeyRepository do
  @moduledoc "Hash-only installation-key storage, separate from tenant API keys."

  @type record :: %{
          id: String.t(),
          digest: binary(),
          inserted_at: DateTime.t(),
          revoked_at: DateTime.t() | nil
        }
  @callback issue(term(), record(), :bootstrap | :replace) :: {:ok, record()} | {:error, atom()}
  @callback fetch(term(), binary()) :: {:ok, record()} | {:error, atom()}
  @callback revoke(term(), String.t(), DateTime.t()) :: {:ok, record()} | {:error, atom()}
end
