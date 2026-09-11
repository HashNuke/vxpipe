defmodule Vxpipe.Gateway.Telephony.ServiceRegistryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.ServiceRegistry

  test "resolves a tenant service before an application-wide service with the same id" do
    registry =
      ServiceRegistry.init!(
        enabled: true,
        services: [
          service(scope: :application, ingress_key: "application_primary"),
          service(
            scope: {:tenant, "tenantkey1234567"},
            ingress_key: "tenant_primary",
            outbound_number: "+15550001001"
          )
        ]
      )

    assert {:ok, tenant_service} =
             ServiceRegistry.fetch_for_tenant(registry, "telnyx-primary", "tenantkey1234567")

    assert tenant_service.identity.ingress_key == "tenant_primary"
    assert tenant_service.outbound_number == "+15550001001"

    assert {:ok, application_service} =
             ServiceRegistry.fetch_for_tenant(registry, "telnyx-primary", "another-tenant")

    assert application_service.identity.ingress_key == "application_primary"
  end

  test "fails closed for another tenant and duplicate scoped service ids" do
    tenant_only =
      ServiceRegistry.init!(
        enabled: true,
        services: [service(scope: {:tenant, "tenantkey1234567"})]
      )

    assert {:error, :service_not_found} =
             ServiceRegistry.fetch_for_tenant(tenant_only, "telnyx-primary", "another-tenant")

    assert_raise ArgumentError, "duplicate telephony service id within scope", fn ->
      ServiceRegistry.init!(
        enabled: true,
        services: [
          service(ingress_key: "first_ingress"),
          service(ingress_key: "second_ingress")
        ]
      )
    end
  end

  defp service(overrides) do
    Keyword.merge(
      [
        id: "telnyx-primary",
        ingress_key: "ingress_telnyx_primary",
        scope: :application,
        provider: :telnyx,
        provider_connection_id: "voice-application-1",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "test-api-key",
        outbound_number: "+15550001000",
        public_base_url: "https://voice.example.test"
      ],
      overrides
    )
  end
end
