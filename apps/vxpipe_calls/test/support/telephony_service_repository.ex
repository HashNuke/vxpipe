defmodule Vxpipe.Calls.TestTelephonyServiceRepository do
  @moduledoc false

  alias Vxpipe.Calls.{ProviderCredential, PublicId, ResolvedProviderCredential}
  alias Vxpipe.Calls.{ResolvedTelephonyService, TelephonyService}

  def repository(tenants, provider \\ "telnyx") do
    bindings = Map.new(tenants, &{{&1.key, "primary-phone"}, snapshot(&1.key, provider)})
    {__MODULE__, bindings}
  end

  def resolve(bindings, tenant_key, name) do
    case Map.fetch(bindings, {tenant_key, name}) do
      {:ok, snapshot} -> {:ok, snapshot}
      :error -> {:error, :telephony_service_not_found}
    end
  end

  def with_active(bindings, tenant_key, requirements, operation) do
    case Enum.find(requirements, &(not available?(bindings, tenant_key, &1))) do
      nil -> operation.()
      missing -> {:error, {:provider_credential_unavailable, missing.path}}
    end
  end

  defp available?(bindings, tenant_key, requirement) do
    case Map.fetch(bindings, {tenant_key, requirement.name}) do
      {:ok, snapshot} ->
        Vxpipe.Calls.TelephonyServices.meets_requirement?(snapshot.service, requirement)

      :error ->
        false
    end
  end

  defp snapshot(tenant_key, provider) do
    {auth_kind, payload, account, public_key} = authentication(provider)

    credential = %ProviderCredential{
      id: PublicId.uuid(),
      tenant_key: tenant_key,
      provider: provider,
      name: "phone",
      auth_kind: auth_kind
    }

    {:ok, service} =
      TelephonyService.new(tenant_key, %{
        "name" => "primary-phone",
        "ingress_key" => "test-#{tenant_key}",
        "provider" => provider,
        "provider_connection_id" => account,
        "credential_id" => credential.id,
        "public_key" => public_key,
        "outbound_number" => "+15550001000"
      })

    %ResolvedTelephonyService{
      service: service,
      credential: %ResolvedProviderCredential{
        credential: credential,
        payload: payload
      }
    }
  end

  defp authentication("telnyx") do
    {"api_key", %{"api_key" => "fixture-phone-private-marker"}, "connection-1",
     Base.encode64(:binary.copy(<<1>>, 32))}
  end

  defp authentication("twilio") do
    account = "AC00000000000000000000000000000000"

    {"account_sid_auth_token",
     %{"account_sid" => account, "auth_token" => "fixture-phone-private-marker"}, account, nil}
  end
end
