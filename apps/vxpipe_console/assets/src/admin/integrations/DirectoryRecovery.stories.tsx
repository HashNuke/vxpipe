import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { IntegrationsDirectory } from "./IntegrationsDirectory";

const saved = { id: "saved-tools", tenant_key: "fixture", endpoint: "https://mcp.example.test/mcp", server_name: "Team tools", auth_method: "none", generation: 1, status: "connected", tool_count: 0, can_edit: true };

const fetchFixture = async (input: RequestInfo | URL, brokenLogo = false, outage = false) => {
  const url = new URL(String(input), "https://console.example.test");
  if (outage && url.pathname.endsWith("/mcp-connections/saved-tools")) return Response.json({ connection: { ...saved, tools: [] } });
  if (outage && !url.pathname.endsWith("/categories")) return Response.json({ tenant: { key: "fixture", name: "Fixture" }, installation_version: "0.1.0", directory_status: "unavailable", connections: [], mcp_connections: [saved], page: null, local_items: [], fallback_items: [
    { id: "provider-telnyx", kind: "provider", name: "Telnyx", connection: { provider_id: "telnyx" }, capabilities: ["telephony"], connections: [], can_connect: true },
    { id: "mcp-saved-tools", kind: "mcp", name: saved.server_name, connection: { endpoint: saved.endpoint }, connections: [], mcp_connections: [saved], can_connect: false },
  ] });
  if (url.pathname.endsWith("/categories")) return Response.json({ categories: [] });
  if (url.searchParams.has("cursor")) return Response.json({ error: { code: "cursor_mismatch" } }, { status: 400 });
  return Response.json({ tenant: brokenLogo ? { key: "fixture", name: "Fixture" } : null, mcp_connections: [], installation_version: "0.1.0", directory_status: "available", connections: [],
    fallback_items: [], local_items: [], page: {
      items: [brokenLogo ? { id: "tools", kind: "mcp", name: "Tools server", connection: { endpoint: "https://mcp.example.test/mcp" }, connections: [], mcp_connections: [], can_connect: false, logo_url: "https://127.0.0.1:1/missing-logo.png" } : { id: "google", kind: "provider", name: "Google AI Studio", connection: { provider_id: "google" }, capabilities: ["llm"], connections: [], can_connect: false }],
      pagination: { total_items: 1, start_index: 1, end_index: 1, next_cursor: null, previous_cursor: null },
    } });
};

function Preview({ brokenLogo = false, outage = false }: { brokenLogo?: boolean; outage?: boolean }) {
  const fetchImpl = useMemo(() => (input: RequestInfo | URL) => fetchFixture(input, brokenLogo, outage), [brokenLogo, outage]);
  return <StoryWorkspace path="/platform/services" theme="light"><MemoryRouter initialEntries={[brokenLogo || outage ? "/t/fixture/services/calendar" : "/platform/services?q=google&cursor=old-page"]}>
    <IntegrationsDirectory tenantKey={brokenLogo || outage ? "fixture" : null} fetchImpl={fetchImpl} csrfToken="fixture" canManageMcps canEdit onManage={() => undefined} />
  </MemoryRouter></StoryWorkspace>;
}

const meta = { title: "Vxpipe/Console/Integrations/Directory recovery", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production cursor recovery with local fixture responses; no directory HTTP requests." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const InvalidPage: Story = {};

// Browsers block this local unsafe port before network I/O.
export const BrokenLogo: Story = { args: { brokenLogo: true } };

export const DirectoryUnavailable: Story = { args: { outage: true } };
