import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo, useState } from "react";
import { Button } from "../Button";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { CustomMcpDialog } from "./CustomMcpDialog";
import type { McpConnection } from "./inventoryApi";
import type { OAuthDraft } from "./oauthDraft";

type Scenario = "custom" | "listed" | "connected" | "cancelled_oauth";
function Preview({ scenario = "custom" }: { scenario?: Scenario }) {
  const endpoint = "https://calendar.example.test/mcp";
  const record = useMemo<McpConnection>(() => ({ id: "retained", endpoint, serverName: "Calendar tools", authMethod: scenario === "cancelled_oauth" ? "oauth" : "bearer",
    generation: 7, status: scenario === "connected" ? "connected" : "revoked", toolCount: 2, canEdit: true,
    ...(scenario === "listed" ? { directoryEntry: { directory_id: "fixture", integration_id: "calendar", revision: 1, name: "Calendar tools", endpoint,
      authentication: { type: "bearer" as const }, setup_notes: "Use a fresh Calendar access token to reconnect your tools." } } : {}) }), [scenario]);
  const [selected, setSelected] = useState<McpConnection | undefined>(scenario === "cancelled_oauth" ? record : undefined);
  const [open, setOpen] = useState(true);
  const [finished, setFinished] = useState(false);
  const initialDraft: OAuthDraft | undefined = scenario === "cancelled_oauth" ? { endpoint, method: "dcr", generation: 7 } : undefined;
  const fetchImpl = useMemo(() => async (url: RequestInfo | URL, init?: RequestInit) => {
    const path = String(url); const body = init?.body ? JSON.parse(String(init.body)) : {};
    if (path.endsWith("/mcp-discovery")) return Response.json({ discovery: { endpoint: body.endpoint, revision: body.revision,
      outcome: scenario === "cancelled_oauth" ? "oauth" : "unknown", suggested_method: scenario === "cancelled_oauth" ? "dcr" : null,
      supported_grants: ["authorization_code"], resource: { resource: endpoint },
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      oauth: { issuer: "https://auth.example.test", registration_endpoint: "https://auth.example.test/register", authorization_endpoint: "https://auth.example.test/authorize",
        token_endpoint: "https://auth.example.test/token", token_endpoint_auth_methods_supported: ["none"] } } });
    if (init?.method === "POST" && path.endsWith("/mcp-connections")) return Response.json({ error: {
      code: scenario === "connected" ? "mcp_connection_exists" : "mcp_reconnect_required", connection_id: record.id, generation: record.generation } }, { status: 409 });
    if (path.endsWith("/oauth")) return Response.json({ authorization_url: "https://auth.example.test/authorize", attempt_id: "fixture", connection_id: record.id });
    if (path.endsWith("/reconnect")) return Response.json({ connection: { id: record.id, generation: 8 } });
    return Response.json({ connection: { id: record.id, tenant_key: "fixture", endpoint, server_name: record.serverName, auth_method: record.authMethod,
      generation: 7, status: record.status, tool_count: 2, can_edit: true, tools: [{ name: "list_events" }, { name: "create_event" }],
      ...(record.directoryEntry ? { directory_entry: record.directoryEntry, directory_id: "fixture/calendar" } : {}) } });
  }, [record, scenario]);
  const finish = () => { setOpen(false); setFinished(true); };
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><main className="admin-page">
    <h1>Integrations</h1><p>In-memory reconnect preview. No provider requests.</p>
    {finished && <p role="status">Reconnect or sign-in handoff simulated.</p>}
    <Button onClick={() => { setSelected(scenario === "cancelled_oauth" ? record : undefined); setOpen(true); }}>Open connection</Button>
    {open && <CustomMcpDialog key={selected?.id ?? "new"} tenantKey="fixture" csrfToken="fixture" fetchImpl={fetchImpl} connection={selected}
      onOpenConnection={setSelected} onClose={() => setOpen(false)} onConnected={finish} onAuthorize={finish} onSessionExpired={() => undefined}
      initialDraft={initialDraft} recoveryNotice={initialDraft ? "Sign-in was cancelled. Enter any credentials again to retry." : undefined} />}
  </main></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/Production reconnect recovery", component: Preview, parameters: { layout: "fullscreen" } } satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Custom: Story = {};
export const AcceptedListing: Story = { args: { scenario: "listed" } };
export const ConnectedDuplicate: Story = { args: { scenario: "connected" } };
export const CancelledOAuth: Story = { args: { scenario: "cancelled_oauth" } };
