defmodule Vxpipe.Calls.ProviderCredentialRepository do
  @moduledoc "Trusted repository port for recoverable provider credentials, separate from API-key hashes."

  alias Vxpipe.Calls.{ProviderCredential, ResolvedProviderCredential}

  @type owner :: :platform | {:tenant, String.t()} | String.t()

  @callback provision(term(), ProviderCredential.t(), map()) ::
              {:ok, ProviderCredential.t()} | {:error, atom()}
  @callback replace(
              term(),
              owner(),
              String.t(),
              String.t(),
              String.t(),
              map(),
              map(),
              DateTime.t() | nil
            ) ::
              {:ok, ProviderCredential.t()} | {:error, atom()}
  @callback list(term(), owner()) :: {:ok, [ProviderCredential.t()]} | {:error, atom()}
  @callback list_bindings(term(), owner()) :: {:ok, map()} | {:error, atom()}
  @callback resolve(term(), owner(), String.t(), String.t()) ::
              {:ok, ResolvedProviderCredential.t()} | {:error, atom()}

  @callback delete(term(), owner(), String.t()) :: :ok | {:error, atom()}
  @optional_callbacks delete: 3, list_bindings: 2

  @doc """
  Validate and hold active bindings while performing the authorized database write.

  The operation must use repositories sharing this context's transaction and must not
  perform network/provider work. Binding locks last until that transaction completes.
  A requirement's optional `allowed_owner` restricts authoring to that credential
  owner and must be checked under the same lock as liveness and optional `identity`.
  Reject mismatched ownership as `{:provider_service_forbidden, requirement.path}`.
  """
  @callback with_active(term(), String.t(), [map()], (-> term())) :: term()
end
