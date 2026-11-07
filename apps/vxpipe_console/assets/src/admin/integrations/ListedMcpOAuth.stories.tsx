import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo, useState } from "react";
import { Button } from "../Button";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { CustomMcpDialog } from "./CustomMcpDialog";
import type { McpListing } from "./listedMcp";

type Registration = "discover" | "cimd" | "dcr" | "preregistered";
type Discovery = "complete" | "partial" | "multiple" | "missing_resource";
function Preview({ registration = "cimd", discovery = "complete", saved = false }: {
  registration?: Registration; discovery?: Discovery; saved?: boolean;
}) {
  const [open, setOpen] = useState(true);
  const [handedOff, setHandedOff] = useState(false);
  const listing = useMemo<McpListing>(() => ({
    reference: { directory_id: "fixture", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant", limit: 20 } },
    entry: { directory_id: "fixture", integration_id: "calendar", revision: 1, name: "Calendar tools", endpoint: "https://calendar.example.test/mcp",
      authentication: { type: "oauth2", registration }, setup_notes: "Sign in to your Calendar account to connect its tools." },
  }), [registration]);
  const connection = useMemo(() => ({ id: "saved", endpoint: listing.entry.endpoint, serverName: listing.entry.name, authMethod: "oauth", generation: 2,
    status: "connected" as const, toolCount: 2, canEdit: true, directoryEntry: listing.entry }), [listing]);
  const fetchImpl = useMemo(() => async (url: RequestInfo | URL, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    if (String(url).endsWith("/mcp-discovery")) {
      const partial = discovery === "partial" && !body.issuer;
      const multiple = discovery === "multiple" && !body.issuer;
      const issuer = body.issuer ?? "https://auth.example.test";
      return Response.json({ discovery: { endpoint: listing.entry.endpoint, revision: body.revision, ...(body.listing ? { listing: listing.entry } : {}),
        ...(body.connection_id ? { connection_id: body.connection_id, generation: body.generation, oauth_registration: { method: "dcr", reusable: true } } : {}),
        outcome: partial ? "partial" : multiple ? "issuer_required" : "oauth", suggested_method: partial || multiple ? null : "cimd",
        supported_grants: partial || multiple ? [] : ["authorization_code"],
        issuers: discovery === "multiple" ? ["https://auth.example.test", "https://other.example.test"] : [issuer],
        ...(discovery === "missing_resource" ? {} : { resource: { resource: listing.entry.endpoint } }),
        oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
        oauth: partial || multiple ? null : { issuer, authorization_endpoint: `${issuer}/authorize`, token_endpoint: `${issuer}/token`,
          registration_endpoint: `${issuer}/register`, client_id_metadata_document_supported: true,
          token_endpoint_auth_methods_supported: ["none", "client_secret_basic"] },
      } });
    }
    if (init?.method === "POST") return Response.json({ authorization_url: "https://auth.example.test/authorize", attempt_id: "fixture", connection_id: "saved" });
    return Response.json({ connection: { ...connection, tools: [{ name: "list_events" }, { name: "create_event" }],
      oauth: { registration_method: "dcr", grant_type: "authorization_code", auth_method: "none" } } });
  }, [listing, connection, discovery]);
  return <StoryWorkspace path="/t/fixture/services" tenant={{ key: "fixture", name: "Fixture" }} theme="light"><main className="admin-page">
    <h1>Integrations</h1>
    {handedOff && <p role="status">Sign-in handoff simulated. No provider navigation or HTTP requests.</p>}
    {saved && <p>Public directory unavailable. Saved connection settings remain available.</p>}
    <Button onClick={() => setOpen(true)}>{saved ? "Manage Calendar tools" : "Connect Calendar tools"}</Button>
    {open && <CustomMcpDialog tenantKey="fixture" csrfToken="fixture" {...(saved ? { connection } : { listing })} fetchImpl={fetchImpl}
      onSessionExpired={() => undefined} onClose={() => setOpen(false)} onConnected={() => setOpen(false)}
      onAuthorize={() => { setHandedOff(true); setOpen(false); }} />}
  </main></StoryWorkspace>;
}
const meta = { title: "Vxpipe/Console/Integrations/Production listed OAuth", component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Fixed listed OAuth forms using in-memory discovery and consent responses. No real HTTP or credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Cimd: Story = {};
export const Dcr: Story = { args: { registration: "dcr" } };
export const RegisteredClient: Story = { args: { registration: "preregistered" } };
export const PartialDiscovery: Story = { args: { discovery: "partial" } };
export const MultipleIssuers: Story = { args: { discovery: "multiple" } };
export const MissingResource: Story = { args: { discovery: "missing_resource" } };
export const SavedDuringOutage: Story = { args: { saved: true, registration: "dcr" } };
