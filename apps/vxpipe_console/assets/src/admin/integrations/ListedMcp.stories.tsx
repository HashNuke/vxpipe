import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { IntegrationsDirectory } from "./IntegrationsDirectory";
import { listedMethod, type McpDirectoryEntry, type McpRecipe } from "./listedMcp";

type Authentication = "api_key" | "bearer" | "basic" | "none";
function fixture(authentication: Authentication, connected: boolean, readOnly: boolean, outage: boolean) {
    let saved = connected;
    let generation = 1;
    const recipe: McpRecipe = authentication === "api_key" ? { type: "api_key", header_name: "X-Calendar-Key" } : { type: authentication };
    const entry: McpDirectoryEntry = { directory_id: "fixture-directory", integration_id: "calendar", revision: 1,
      name: "Calendar tools", endpoint: "https://calendar.example.test/mcp", authentication: recipe,
      setup_notes: "Create credentials in your Calendar account, then enter them below.",
      setup_url: "https://calendar.example.test/settings", documentation_url: "https://calendar.example.test/docs" };
    const reference = { directory_id: entry.directory_id, integration_id: entry.integration_id, entry_revision: entry.revision,
      page: { scope: "tenant", category: "calendar", limit: 20 } };
    const record = () => ({ id: "fixture-listed", tenant_key: "fixture", endpoint: entry.endpoint, server_name: entry.name,
      auth_method: listedMethod(entry), generation, status: "connected", tool_count: 2, can_edit: !readOnly,
      directory_id: `${entry.directory_id}/${entry.integration_id}`, directory_entry: entry });
    return async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = String(input);
      const body = init?.body ? JSON.parse(String(init.body)) : {};
      if (init?.method === "POST") { saved = true; return Response.json({ connection: record() }, { status: 201 }); }
      if (init?.method === "PATCH") { if (!body.refresh_tools) generation++; return Response.json({ connection: record() }); }
      if (init?.method === "DELETE") { saved = false; generation++; return Response.json({ connection: { ...record(), status: "revoked" } }); }
      if (path.endsWith("/mcp-connections/fixture-listed")) return Response.json({ connection: { ...record(), tools: [{ name: "list_events" }, { name: "create_event" }] } });
      if (path.endsWith("/categories")) return outage ? new Response(null, { status: 503 }) : Response.json({ categories: [{ id: "calendar", name: "Calendar", integration_count: 1 }] });
      const row = { id: "calendar", revision: 1, name: entry.name, kind: "mcp", summary: "Find and manage calendar events.",
        listing: reference, connection: { endpoint: entry.endpoint, authentication: recipe }, connections: [], mcp_connections: saved ? [record()] : [], can_connect: !saved && !readOnly,
        setup_notes: entry.setup_notes, setup_url: entry.setup_url, documentation_url: entry.documentation_url };
      return Response.json({ tenant: { key: "fixture", name: "Fixture" }, installation_version: "0.1.0", connections: [], mcp_connections: saved ? [record()] : [],
        directory_status: outage ? "local" : "available", fallback_items: [], local_items: saved ? [row] : [],
        page: outage ? null : { items: [row], pagination: { total_items: 1, start_index: 1, end_index: 1, next_cursor: null, previous_cursor: null } } });
    };
}
function Preview({ authentication = "api_key", connected = false, readOnly = false, outage = false }: {
  authentication?: Authentication; connected?: boolean; readOnly?: boolean; outage?: boolean;
}) {
  const fetchImpl = useMemo(() => fixture(authentication, connected, readOnly, outage), [authentication, connected, readOnly, outage]);
  const path = outage ? "/t/fixture/services" : "/t/fixture/services/calendar";
  return <StoryWorkspace path={path} tenant={{ key: "fixture", name: "Fixture" }} theme="light"><MemoryRouter initialEntries={[path]}><main className="admin-page">
    <IntegrationsDirectory tenantKey="fixture" actorId="fixture-user" csrfToken="fixture" canManageMcps={!readOnly} fetchImpl={fetchImpl} onManage={() => undefined} />
  </main></MemoryRouter></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/Production listed MCP", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production listed static MCP forms with in-memory responses. No real HTTP calls or provider credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const ApiKey: Story = {};
export const Bearer: Story = { args: { authentication: "bearer" } };
export const Basic: Story = { args: { authentication: "basic" } };
export const Anonymous: Story = { args: { authentication: "none" } };
export const SavedDuringOutage: Story = { args: { connected: true, outage: true } };
export const ReadOnly: Story = { args: { connected: true, readOnly: true } };
