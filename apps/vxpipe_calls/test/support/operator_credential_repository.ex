defmodule Vxpipe.Calls.TestOperatorCredentialRepository do
  @behaviour Vxpipe.Calls.ProviderCredentialRepository

  def repository(owner, result), do: {__MODULE__, {owner, result}}

  @impl true
  def provision({owner, result}, credential, payload) do
    send(owner, {:operator_credential_provisioned, credential, payload})
    result
  end

  @impl true
  def replace(
        {owner, result},
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        _hints,
        _last_validated_at
      ) do
    send(
      owner,
      {:operator_credential_replaced, tenant_key, credential_id, provider, auth_kind, payload}
    )

    result
  end

  @impl true
  def list(_context, _tenant_key), do: {:error, :not_implemented}

  @impl true
  def resolve(_context, _tenant_key, _provider, _name), do: {:error, :not_implemented}

  @impl true
  def with_active(_context, _tenant_key, _requirements, operation), do: operation.()
end
