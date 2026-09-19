defmodule Vxpipe.Console.Test.OperatorCredentialRepository do
  @behaviour Vxpipe.Calls.ProviderCredentialRepository

  @impl true
  def provision({owner, result}, credential, payload) do
    send(owner, {:operator_credential_created, credential, payload})
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
        last_validated_at
      ) do
    send(
      owner,
      {:operator_credential_replaced, tenant_key, credential_id, provider, auth_kind, payload,
       last_validated_at}
    )

    result
  end

  @impl true
  def list_bindings({owner, result}, scope) do
    send(owner, {:operator_bindings_requested, scope})
    result
  end

  @impl true
  def set_policy({owner, result}, tenant, provider, name, policy) do
    send(owner, {:operator_policy_changed, tenant, provider, name, policy})
    result
  end

  @impl true
  def list(_context, _tenant_key), do: {:error, :not_implemented}

  @impl true
  def resolve(_context, _tenant_key, _provider, _name), do: {:error, :not_implemented}

  @impl true
  def with_active(_context, _tenant_key, _requirements, operation), do: operation.()
end
