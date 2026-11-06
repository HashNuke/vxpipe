import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo, useState } from "react";
import { Button } from "../Button";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { CustomMcpDialog } from "./CustomMcpDialog";
import type { OAuthMethod } from "./oauthForm";

const fixtureFetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const body = init?.body ? JSON.parse(String(init.body)) : {};
  if (!init?.method) return Response.json({ connection: { id: "fixture", generation: 1, tools: [{ name: "list_events" }, { name: "create_event" }] } });
  if (String(input).endsWith("mcp-discovery")) return Response.json({ discovery: {
    endpoint: body.endpoint, revision: body.revision, outcome: "anonymous", suggested_method: "none", server_name: "Fixture tools",
  } });
  return Response.json({ connection: { id: "fixture", generation: body.refresh_tools ? body.generation : (body.generation ?? 0) + 1, server_name: "Fixture tools", tool_count: 2 } }, { status: 201 });
};
function Preview({ manage = false, readOnly = false, unsupportedOAuth = false, oauthMethod, machine = false }: { manage?: boolean; readOnly?: boolean; unsupportedOAuth?: boolean; oauthMethod?: OAuthMethod; machine?: boolean }) {
  const fetchImpl = useMemo(() => async (input: RequestInfo | URL, init?: RequestInit) => {
    if (unsupportedOAuth && String(input).endsWith("mcp-discovery")) {
      const body = JSON.parse(String(init?.body));
      return Response.json({ discovery: { endpoint: body.endpoint, revision: body.revision,
        outcome: "unsupported_oauth", suggested_method: null } });
    }
    if (oauthMethod && String(input).endsWith("mcp-discovery")) {
      const body = JSON.parse(String(init?.body));
      return Response.json({ discovery: { ...body, outcome: "oauth", suggested_method: oauthMethod,
        supported_grants: machine ? ["client_credentials"] : ["authorization_code", "client_credentials"],
        issuers: ["https://auth.example.test"], resource: { scopes_supported: ["tools.read"] },
        oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
        oauth: { issuer: "https://auth.example.test", authorization_endpoint: "https://auth.example.test/authorize", token_endpoint: "https://auth.example.test/token",
          registration_endpoint: "https://auth.example.test/register", client_id_metadata_document_supported: true,
          token_endpoint_auth_methods_supported: ["none", "client_secret_basic", "client_secret_post", "private_key_jwt"], token_endpoint_auth_signing_alg_values_supported: ["RS256", "ES256"] } } });
    }
    if (oauthMethod && String(input).endsWith("mcp-oauth")) return Response.json({ authorization_url: "https://auth.example.test/authorize?state=fixture", attempt_id: "fixture-attempt", connection_id: "fixture" });
    return fixtureFetch(input, init);
  }, [unsupportedOAuth, oauthMethod, machine]);
  const [open, setOpen] = useState(true);
  const [connected, setConnected] = useState(false);
  const [authorizing, setAuthorizing] = useState(false);
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><main className="admin-page"><h1>Integrations</h1>{connected && <p role="status">Fixture tools connected. No tools available.</p>}{authorizing && <p role="status">OAuth handoff simulated. No HTTP requests or provider navigation.</p>}<Button onClick={() => setOpen(true)}>Connect other MCP</Button>{open && <CustomMcpDialog connection={manage ? { id: "fixture", endpoint: "https://mcp.example.test/mcp", serverName: "Fixture tools", authMethod: "bearer", generation: 1, status: "connected", toolCount: 2, canEdit: !readOnly } : undefined} tenantKey="fixture" csrfToken="fixture" fetchImpl={fetchImpl} onSessionExpired={() => undefined} onClose={() => setOpen(false)} onConnected={() => { setConnected(true); setOpen(false); }} onAuthorize={() => { setAuthorizing(true); setOpen(false); }} />}</main></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/Production custom MCP", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production dialog with local fixture responses. No real HTTP or saved credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Connect: Story = {};

export const Manage: Story = { args: { manage: true } };
export const ReadOnly: Story = { args: { manage: true, readOnly: true } };

export const UnsupportedOAuth: Story = { args: { unsupportedOAuth: true } };
export const OAuthCimd: Story = { args: { oauthMethod: "cimd" } };
export const OAuthDcr: Story = { args: { oauthMethod: "dcr" } };
export const OAuthOwnClient: Story = { args: { oauthMethod: "own_client" } };
export const OAuthMachine: Story = { args: { oauthMethod: "own_client", machine: true } };
