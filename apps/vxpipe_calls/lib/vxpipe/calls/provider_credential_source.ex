defmodule Vxpipe.Calls.ProviderCredentialSource do
  @moduledoc "Bridges Engine's private credential source to the tenant repository."

  @behaviour Vxpipe.CallEngine.CredentialSource

  alias Vxpipe.CallEngine.ProviderCredential
  alias Vxpipe.Calls.CallSpecCredentials

  @impl true
  def resolve(:configured, tenant_id, provider, name),
    do: resolve([], tenant_id, provider, name)

  def resolve(options, tenant_id, provider, name) when is_list(options) do
    selection = %{provider: provider, credential_name: name}

    with {:ok, resolved} <- CallSpecCredentials.resolve(tenant_id, selection, options) do
      credential = resolved.credential

      {:ok,
       %ProviderCredential{
         id: credential.id,
         tenant_id: credential.tenant_key,
         provider: credential.provider,
         name: credential.name,
         version: credential.version,
         auth_kind: credential.auth_kind,
         payload: resolved.payload
       }}
    end
  end
end
