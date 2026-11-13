import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { IntegrationsApp } from "../../IntegrationsApp";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { TelephonyApplication } from "../telephonyApplicationsApi";

const tenant = { key: "Acme123456789012", name: "Acme" };

function fixture() {
  let application: TelephonyApplication = {
    id: "5eef6e68-11aa-434a-9a99-abc123def456", name: "support",
    provider_connection_id: null, outbound_number: null, published_routes: [],
  };
  const credential = { provider: "telnyx", name: "telnyx", source: "platform", status: "connected",
    credential_id: "fixture-platform-credential", platform_available: true,
    saved_fields: ["api_key", "public_key"], last_validated_at: null, can_edit: false };
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = new URL(String(input), "https://console.example.test").pathname;
    if (path.endsWith("/categories")) return Response.json({ categories: [] });
    if (path.endsWith("/telnyx-connection")) {
      if (init?.method === "PATCH") {
        const changes = JSON.parse(String(init.body));
        application = { ...application, provider_connection_id: changes.application_id };
      }
      return Response.json({ platform_application_id: "shared-app", credential, applications: [application],
        webhook_urls: { platform: "https://calls.example.test/webhooks/platform/telnyx",
          tenant: `https://calls.example.test/webhooks/tenants/${tenant.key}/telnyx` } });
    }
    if (path.includes("/telephony-applications")) {
      if (init?.method === "PATCH") {
        application = { ...application, ...JSON.parse(String(init.body)) };
        return Response.json({ application });
      }
      return Response.json({ tenant, applications: [application], truncated: false });
    }
    if (path.endsWith("/service-bindings")) return Response.json({ tenant, bindings: [credential],
      model_catalog: modelCatalogFixture, provider_capabilities: { telnyx: ["credential", "telephony"] } });
    return Response.json({ tenant, installation_version: "0.1.0", directory_status: "local", page: null,
      connections: [credential], mcp_connections: [], fallback_items: [], local_items: [{
        id: "provider-telnyx", kind: "provider", name: "Telnyx", connection: { provider_id: "telnyx" },
        capabilities: ["telephony"], can_connect: false, connections: [credential],
      }] });
  };
}

function Preview({ phoneRouting = false, readOnly = false }: { phoneRouting?: boolean; readOnly?: boolean }) {
  const fetchImpl = useMemo(() => fixture(), []);
  return <MemoryRouter initialEntries={[`/t/${tenant.key}/services${phoneRouting ? "/telephony" : ""}`]}>
    <IntegrationsApp scope={{ kind: "tenant", tenantKey: tenant.key, tenantName: tenant.name }}
      csrfToken="fixture" fetchImpl={fetchImpl} canEdit={false} canEditApplications={!readOnly} onNavigate={() => undefined} />
  </MemoryRouter>;
}

const meta = {
  title: "Vxpipe/Console/Services/Telnyx permissions", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component:
    "Production Telnyx components with in-memory saves and application-only permissions. No provider calls or stored credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const ApplicationWriter: Story = {};
export const InheritedCallerNumber: Story = { args: { phoneRouting: true } };
export const ReadOnly: Story = { args: { readOnly: true } };
