defmodule Vxpipe.Calls.TestOperatorCredentialRepository do
  @behaviour Vxpipe.Calls.ProviderCredentialRepository

  def repository(owner, result), do: {__MODULE__, {owner, result}}

  @impl true
  def provision({owner, result}, credential, payload) do
    send(owner, {:operator_credential_provisioned, credential, payload})
    result
  end

  @impl true
  def list(_context, _tenant_key), do: {:error, :not_implemented}

  @impl true
  def resolve(_context, _tenant_key, _provider, _name), do: {:error, :not_implemented}

  @impl true
  def with_active(_context, _tenant_key, _requirements, operation), do: operation.()
end
