import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { IntegrationsDirectory } from "./IntegrationsDirectory";

const fetchFixture = async (input: RequestInfo | URL, brokenLogo = false) => {
  const url = new URL(String(input), "https://console.example.test");
  if (url.pathname.endsWith("/categories")) return Response.json({ categories: [] });
  if (url.searchParams.has("cursor")) return Response.json({ error: { code: "cursor_mismatch" } }, { status: 400 });
  return Response.json({ tenant: brokenLogo ? { key: "fixture", name: "Fixture" } : null, mcp_connections: [], installation_version: "0.1.0", directory_status: "available", connections: [],
    fallback_items: [], local_items: [], page: {
      items: [brokenLogo ? { id: "tools", kind: "mcp", name: "Tools server", connection: { endpoint: "https://mcp.example.test/mcp" }, connections: [], mcp_connections: [], can_connect: false, logo_url: "https://127.0.0.1:1/missing-logo.png" } : { id: "google", kind: "provider", name: "Google AI Studio", connection: { provider_id: "google" }, capabilities: ["llm"], connections: [], can_connect: false }],
      pagination: { total_items: 1, start_index: 1, end_index: 1, next_cursor: null, previous_cursor: null },
    } });
};

function Preview({ brokenLogo = false }: { brokenLogo?: boolean }) {
  const fetchImpl = useMemo(() => (input: RequestInfo | URL) => fetchFixture(input, brokenLogo), [brokenLogo]);
  return <StoryWorkspace path="/platform/services" theme="light"><MemoryRouter initialEntries={[brokenLogo ? "/t/fixture/services/calendar" : "/platform/services?q=google&cursor=old-page"]}>
    <IntegrationsDirectory tenantKey={brokenLogo ? "fixture" : null} fetchImpl={fetchImpl} onManage={() => undefined} />
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
