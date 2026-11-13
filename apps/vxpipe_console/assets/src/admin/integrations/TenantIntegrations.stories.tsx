import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { IntegrationsApp } from "../../IntegrationsApp";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { modelCatalogFixture } from "../modelCatalogFixtures";

function fixture(initialConnected: boolean, readOnly: boolean, inventoryDelay: number) {
  let connected = initialConnected;
  let generation = 1;
  const tenant = { key: "fixture", name: "Fixture" };
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path.includes("/integrations?") && inventoryDelay) await new Promise(resolve => setTimeout(resolve, inventoryDelay));
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    const saved = () => ({ id: "fixture-mcp", tenant_key: tenant.key, server_name: "Fixture tools",
      endpoint: "https://mcp.example.test/mcp", auth_method: "none", generation, status: "connected", tool_count: 2, can_edit: !readOnly });
    if (path.endsWith("/mcp-discovery")) return Response.json({ discovery: { ...body, outcome: "anonymous", suggested_method: "none", server_name: "Fixture tools" } });
    if (init?.method === "POST") { connected = true; return Response.json({ connection: saved() }, { status: 201 }); }
    if (init?.method === "PATCH") { if (!body.refresh_tools) generation++; return Response.json({ connection: saved() }); }
    if (init?.method === "DELETE") { connected = false; generation++; return Response.json({ connection: { ...saved(), status: "revoked" } }); }
    if (path.endsWith("/mcp-connections/fixture-mcp")) return Response.json({ connection: { ...saved(), tools: [{ name: "list_events" }, { name: "create_event" }] } });
    if (path.endsWith("/categories")) return Response.json({ categories: [] });
    if (path.includes("/integrations?")) return Response.json({ tenant, installation_version: "0.1.0", directory_status: "local", connections: [],
      mcp_connections: connected ? [saved()] : [], page: null, fallback_items: [], local_items: connected ? [{ id: "mcp-fixture-mcp", kind: "mcp", name: "Fixture tools",
        connection: { endpoint: saved().endpoint }, connections: [], mcp_connections: [saved()], can_connect: false }] : [] });
    return Response.json({ tenant, bindings: [], model_catalog: modelCatalogFixture, provider_capabilities: { google: ["credential", "llm"] } });
  };
}
function Preview({ connected = false, readOnly = false, inventoryDelay = 0 }: { connected?: boolean; readOnly?: boolean; inventoryDelay?: number }) {
  const fetchImpl = useMemo(() => fixture(connected, readOnly, inventoryDelay), [connected, readOnly, inventoryDelay]);
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><MemoryRouter initialEntries={["/t/fixture/services"]}>
    <IntegrationsApp scope={{ kind: "tenant", tenantKey: "fixture", tenantName: "Fixture" }} csrfToken="fixture" canEdit={!readOnly} canManageMcps={!readOnly} fetchImpl={fetchImpl} onNavigate={() => undefined} />
  </MemoryRouter></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/Production tenant inventory", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production tenant inventory and MCP dialogs with in-memory responses; no real network or credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Connect: Story = {};
export const SlowNavigation: Story = { args: { connected: true, inventoryDelay: 3000 } };
export const Connected: Story = { args: { connected: true } };
export const ReadOnly: Story = { args: { connected: true, readOnly: true } };

function InheritedPreview() {
  const fetchImpl = useMemo(() => {
    const tenant = { key: "fixture", name: "Fixture" };
    const binding = { provider: "google", name: "google", source: "platform", status: "connected",
      credential_id: "fixture-platform-google", platform_available: true, saved_fields: ["api_key"], last_validated_at: null, can_edit: false };
    return async (input: RequestInfo | URL) => Response.json(String(input).endsWith("/categories") ? { categories: [] } : String(input).includes("/integrations?") ? {
      tenant, installation_version: "0.1.0", directory_status: "local", connections: [binding], page: null,
      fallback_items: [], local_items: [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
        connection: { provider_id: "google" }, capabilities: ["llm"], can_connect: false, connections: [binding] }],
    } : { tenant, bindings: [binding], model_catalog: modelCatalogFixture, provider_capabilities: { google: ["credential", "llm"] } });
  }, []);
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><MemoryRouter initialEntries={["/t/fixture/services"]}>
    <IntegrationsApp scope={{ kind: "tenant", tenantKey: "fixture", tenantName: "Fixture" }} csrfToken="fixture" fetchImpl={fetchImpl} onNavigate={() => undefined} />
  </MemoryRouter></StoryWorkspace>;
}
export const InheritedNative: Story = { render: () => <InheritedPreview /> };
