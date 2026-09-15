defmodule Vxpipe.CallEngine.TestTenantCredentialSource do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.CredentialSource

  alias Vxpipe.CallEngine.ProviderCredential

  @impl true
  def resolve({:store, observer, store}, tenant_id, provider, name) do
    resolve({observer, Agent.get(store, & &1)}, tenant_id, provider, name)
  end

  def resolve({:await, observer, bindings}, tenant_id, provider, name) do
    send(observer, {:tenant_credential_resolver_waiting, self()})

    receive do
      :resolve -> resolve({observer, bindings}, tenant_id, provider, name)
    after
      5_000 -> {:error, :unavailable}
    end
  end

  def resolve({observer, bindings}, tenant_id, provider, name) do
    send(observer, {:tenant_credential_resolved, tenant_id, provider, name})

    case Map.fetch(bindings, {tenant_id, provider, name}) do
      {:ok, payload} ->
        {:ok,
         %ProviderCredential{
           id: provider <> "-credential",
           tenant_id: tenant_id,
           provider: provider,
           name: name,
           version: 1,
           auth_kind: "api_key",
           payload: payload
         }}

      :error ->
        {:error, :unavailable}
    end
  end
end
