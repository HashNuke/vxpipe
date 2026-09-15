defmodule Vxpipe.Calls.ProviderCredentialRepository do
  @moduledoc "Trusted repository port for recoverable provider credentials, separate from API-key hashes."

  alias Vxpipe.Calls.{ProviderCredential, ResolvedProviderCredential}

  @callback provision(term(), ProviderCredential.t(), map()) ::
              {:ok, ProviderCredential.t()} | {:error, atom()}
  @callback list(term(), String.t()) :: {:ok, [ProviderCredential.t()]} | {:error, atom()}
  @callback resolve(term(), String.t(), String.t(), String.t()) ::
              {:ok, ResolvedProviderCredential.t()} | {:error, atom()}

  @doc """
  Validate and hold active bindings while performing the authorized database write.

  The operation must use repositories sharing this context's transaction and must not
  perform network/provider work. Binding locks last until that transaction completes.
  """
  @callback with_active(term(), String.t(), [map()], (-> term())) :: term()
end
