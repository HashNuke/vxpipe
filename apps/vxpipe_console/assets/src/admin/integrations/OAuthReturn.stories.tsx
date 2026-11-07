import type { Meta, StoryObj } from "@storybook/react-vite";
import { useEffect, useMemo, useState } from "react";
import { MemoryRouter } from "react-router";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { IntegrationsDirectory } from "./IntegrationsDirectory";
import { saveOAuthDraft } from "./oauthDraft";

function Preview({ connected = false, expiredCursor = false, retained = false, recoveryOutage = false }: { connected?: boolean; expiredCursor?: boolean; retained?: boolean; recoveryOutage?: boolean }) {
  const returnTo = `/t/fixture/services/search?q=calendar${expiredCursor ? "&cursor=expired" : ""}`;
  const [ready, setReady] = useState(false);
  useEffect(() => {
    saveOAuthDraft({ actorId: "fixture-actor", tenantKey: "fixture", attemptId: "fixture-attempt", connectionId: "fixture-connection", returnTo,
      draft: { endpoint: "https://mcp.example.test/mcp", method: "dcr", ...(retained ? { generation: 2 } : {}) } });
    setReady(true);
  }, [returnTo, retained]);
  const fetchImpl = useMemo(() => {
    let recoveryReads = 0;
    return async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).endsWith("/categories")) return Response.json({ categories: [] });
    if (String(input).includes("cursor=")) return Response.json({ error: { code: "cursor_expired" } }, { status: 410 });
    if (String(input).endsWith("/mcp-discovery")) return Response.json({ discovery: { ...JSON.parse(String(init?.body)), outcome: "oauth", suggested_method: "dcr",
      supported_grants: ["authorization_code"], issuers: ["https://auth.example.test"],
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      oauth: { issuer: "https://auth.example.test", registration_endpoint: "https://auth.example.test/register", token_endpoint_auth_methods_supported: ["none"] } } });
    if (String(input).endsWith("/mcp-oauth") || String(input).endsWith("/oauth")) return Response.json({ authorization_url: "https://auth.example.test/authorize?state=fixture", attempt_id: "fixture-retry", connection_id: "fixture-connection" });
    if (String(input).includes("retained_generation=2")) {
      if (recoveryOutage && recoveryReads++ === 0) return new Response(null, { status: 503 });
      return Response.json({ connection: { id: "fixture-connection", tenant_key: "fixture", endpoint: "https://mcp.example.test/mcp", server_name: "Calendar tools",
        auth_method: "oauth", generation: 2, status: "revoked", tool_count: 0, can_edit: true } });
    }
    return Response.json({ tenant: { key: "fixture", name: "Fixture" }, installation_version: "0.1.0", directory_status: "local", connections: [],
      mcp_connections: connected ? [{ id: "fixture-connection", tenant_key: "fixture", endpoint: "https://mcp.example.test/mcp", server_name: "Calendar tools",
        auth_method: "oauth", generation: 1, status: "connected", tool_count: 0, can_edit: true }] : [], page: null, local_items: [], fallback_items: [] });
    };
  }, [connected, recoveryOutage]);
  const [handoff, setHandoff] = useState(false);
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><main className="admin-page">
    {handoff ? <p role="status">Retry handoff simulated. No provider navigation.</p> : ready && <MemoryRouter initialEntries={[`${returnTo}&mcp=${connected ? "connected" : "denied"}&mcp_attempt=fixture-attempt`]}>
      <IntegrationsDirectory actorId="fixture-actor" tenantKey="fixture" csrfToken="fixture" canManageMcps fetchImpl={fetchImpl} onManage={() => undefined} onAuthorizationRedirect={() => setHandoff(true)} />
    </MemoryRouter>}
  </main></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/OAuth return", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production OAuth return with a synthetic tab-local draft and in-memory HTTP responses." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Denied: Story = {};
export const Connected: Story = { args: { connected: true } };
export const ExpiredCursor: Story = { args: { expiredCursor: true } };
export const RetainedDenied: Story = { args: { retained: true } };
export const RetainedOutage: Story = { args: { retained: true, recoveryOutage: true } };
