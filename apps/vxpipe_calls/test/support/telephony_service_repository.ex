defmodule Vxpipe.Calls.TestTelephonyServiceRepository do
  @moduledoc false

  alias Vxpipe.Calls.{ProviderCredential, PublicId, ResolvedProviderCredential}
  alias Vxpipe.Calls.{ResolvedTelephonyService, TelephonyService}

  def repository(tenants) do
    bindings = Map.new(tenants, &{{&1.key, "primary-phone"}, snapshot(&1.key)})
    {__MODULE__, bindings}
  end

  def resolve(bindings, tenant_key, name) do
    case Map.fetch(bindings, {tenant_key, name}) do
      {:ok, snapshot} -> {:ok, snapshot}
      :error -> {:error, :telephony_service_not_found}
    end
  end

  def with_active(bindings, tenant_key, requirements, operation) do
    case Enum.find(requirements, &(not Map.has_key?(bindings, {tenant_key, &1.name}))) do
      nil -> operation.()
      missing -> {:error, {:provider_credential_unavailable, missing.path}}
    end
  end

  defp snapshot(tenant_key) do
    credential = %ProviderCredential{
      id: PublicId.uuid(),
      tenant_key: tenant_key,
      provider: "telnyx",
      name: "phone",
      auth_kind: "api_key"
    }

    {:ok, service} =
      TelephonyService.new(tenant_key, %{
        "name" => "primary-phone",
        "ingress_key" => "test-#{tenant_key}",
        "provider" => "telnyx",
        "provider_connection_id" => "connection-1",
        "credential_id" => credential.id,
        "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
      })

    %ResolvedTelephonyService{
      service: service,
      credential: %ResolvedProviderCredential{
        credential: credential,
        payload: %{"api_key" => "fixture-phone-private-marker"}
      }
    }
  end
end
