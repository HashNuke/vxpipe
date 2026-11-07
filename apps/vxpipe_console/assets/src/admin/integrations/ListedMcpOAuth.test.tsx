import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";
import type { McpListing } from "./listedMcp";

afterEach(cleanup);
const endpoint = "https://calendar.example.test/mcp";
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };
function listing(registration: "discover" | "cimd" | "dcr" | "preregistered"): McpListing {
  return { reference: { directory_id: "directory", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant", limit: 20 } },
    entry: { directory_id: "directory", integration_id: "calendar", revision: 1, name: "Calendar", endpoint,
      authentication: { type: "oauth2", registration } } };
}
function fixture(entry: McpListing, outcome = "oauth") {
  return vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: {
      endpoint, revision: JSON.parse(String(init?.body)).revision, listing: entry.entry, outcome,
      connection_id: JSON.parse(String(init?.body)).connection_id, generation: JSON.parse(String(init?.body)).generation,
      oauth_registration: { method: entry.entry.authentication.type === "oauth2" && entry.entry.authentication.registration === "preregistered" ? "own_client" : "dcr", reusable: false },
      suggested_method: outcome === "oauth" ? "cimd" : null, supported_grants: outcome === "oauth" ? ["authorization_code"] : [],
      issuers: ["https://auth.example.test"], resource: { resource: endpoint, scopes_supported: ["tools.read"] },
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      oauth: { issuer: "https://auth.example.test", token_endpoint: "https://auth.example.test/token", authorization_endpoint: "https://auth.example.test/authorize",
        registration_endpoint: "https://auth.example.test/register", client_id_metadata_document_supported: true,
        token_endpoint_auth_methods_supported: ["none", "client_secret_basic"] },
    } });
    return Response.json({ authorization_url: "https://auth.example.test/authorize", attempt_id: "attempt", connection_id: "connection" }, { status: 201 });
  });
}
const enter = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });

test.each(["discover", "cimd", "dcr", "preregistered"] as const)("listed %s keeps fixed configuration and sends only required client values", async registration => {
  const entry = listing(registration);
  const fetchImpl = fixture(entry);
  const authorize = vi.fn();
  render(<CustomMcpDialog {...defaults} listing={entry} fetchImpl={fetchImpl} onAuthorize={authorize} />);
  await screen.findByText("OAuth settings discovered.");
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Authentication Type")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Grant type")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "OAuth endpoints and scopes" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Additional parameters" })).not.toBeInTheDocument();
  if (registration === "dcr") enter("Initial registration token", "synthetic-initial");
  if (registration === "preregistered") {
    expect(screen.getByLabelText("Callback URL")).toHaveValue("https://console.example.test/oauth/mcp/callback");
    expect(screen.getByLabelText("Client authentication")).toHaveValue("");
    enter("Client ID", "registered"); enter("Client authentication", "client_secret_basic"); enter("Client secret", "synthetic-secret");
  } else expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(authorize).toHaveBeenCalledOnce());
  const discovery = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-discovery"));
  expect(JSON.parse(String(discovery?.[1]?.body))).toEqual({ listing: entry.reference, revision: "0" });
  const request = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-oauth"));
  expect(JSON.parse(String(request?.[1]?.body))).toEqual({ listing: entry.reference, revision: "0",
    ...(registration === "dcr" ? { initial_access_token: "synthetic-initial" } : {}),
    ...(registration === "preregistered" ? { credentials: { client_id: "registered", client_auth_method: "client_secret_basic", client_secret: "synthetic-secret" } } : {}),
  });
  expect(authorize.mock.calls[0][1]).toMatchObject({ listing: entry });
  expect(JSON.stringify(authorize.mock.calls[0][1])).not.toContain("synthetic");
});

test("a listed OAuth recipe cannot become anonymous when discovery is unknown", async () => {
  const entry = listing("discover");
  const fetchImpl = fixture(entry, "unknown");
  render(<CustomMcpDialog {...defaults} listing={entry} fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("button", { name: "Retry discovery" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect" })).toBeDisabled();
  expect(screen.queryByLabelText("Authentication Type")).not.toBeInTheDocument();
  expect(fetchImpl.mock.calls.every(([url]) => String(url).endsWith("/mcp-discovery"))).toBe(true);
});

test("manual issuer recovery stays mounted while the user types and discovery restarts", async () => {
  const entry = listing("discover");
  const fetchImpl = fixture(entry, "partial");
  render(<CustomMcpDialog {...defaults} listing={entry} fetchImpl={fetchImpl} />);
  const input = await screen.findByLabelText("Authorization server URL");
  input.focus();
  fireEvent.change(input, { target: { value: "h" } });
  expect(screen.getByLabelText("Authorization server URL")).toBe(input);
  expect(input).toHaveFocus();
  fireEvent.change(input, { target: { value: "https://auth.example.test" } });
  expect(screen.getByLabelText("Authorization server URL")).toBe(input);
  expect(input).toHaveValue("https://auth.example.test");
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2));
  expect(screen.getByLabelText("Authorization server URL")).toBe(input);
});

test("saved listed OAuth discovers its accepted endpoint and replaces without consulting the directory", async () => {
  const entry = listing("dcr");
  const connection = { id: "saved", endpoint, serverName: "Calendar", authMethod: "oauth", generation: 7, status: "connected" as const, toolCount: 0, canEdit: true, directoryEntry: entry.entry };
  const authorize = vi.fn();
  const fresh = fixture(entry);
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/saved")) return Response.json({ connection: { ...connection, tools: [], oauth: { registration_method: "dcr", grant_type: "authorization_code", auth_method: "none" } } });
    return fresh(url, init);
  });
  render(<CustomMcpDialog {...defaults} connection={connection} fetchImpl={fetchImpl} onAuthorize={authorize} />);
  await waitFor(() => expect(screen.getByRole("button", { name: "Test connection" })).toBeEnabled());
  fireEvent.click(screen.getByLabelText("Replace credentials"));
  await screen.findByText("OAuth settings discovered.");
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() => expect(authorize).toHaveBeenCalledOnce());
  const discovery = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-discovery"));
  expect(JSON.parse(String(discovery?.[1]?.body))).toEqual({ connection_id: "saved", generation: 7, revision: "0" });
  const request = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/saved/oauth"));
  expect(JSON.parse(String(request?.[1]?.body))).toEqual({ generation: 7, revision: "0" });
  expect(authorize.mock.calls[0][1]).not.toHaveProperty("listing");
});

test("saved reusable DCR needs no new registration endpoint or client credentials", async () => {
  const entry = listing("discover");
  const connection = { id: "saved", endpoint, serverName: "Calendar", authMethod: "oauth", generation: 7, status: "connected" as const, toolCount: 0, canEdit: true, directoryEntry: entry.entry };
  const authorize = vi.fn();
  const fresh = fixture(entry);
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/saved")) return Response.json({ connection: { ...connection, tools: [], oauth: { registration_method: "dcr", grant_type: "authorization_code", auth_method: "none" } } });
    const response = await fresh(url, init);
    if (!String(url).endsWith("/mcp-discovery")) return response;
    const body = await response.json();
    delete body.discovery.oauth.registration_endpoint;
    delete body.discovery.oauth.client_id_metadata_document_supported;
    return Response.json({ discovery: { ...body.discovery, connection_id: "saved", generation: 7, oauth_registration: { method: "dcr", reusable: true } } });
  });
  render(<CustomMcpDialog {...defaults} connection={connection} fetchImpl={fetchImpl} onAuthorize={authorize} />);
  await waitFor(() => expect(screen.getByRole("button", { name: "Test connection" })).toBeEnabled());
  fireEvent.click(screen.getByLabelText("Replace credentials"));
  await screen.findByText("OAuth settings discovered.");
  expect(screen.queryByLabelText("Client ID")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Initial registration token")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() => expect(authorize).toHaveBeenCalledOnce());
  const request = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/saved/oauth"));
  expect(JSON.parse(String(request?.[1]?.body))).toEqual({ generation: 7, revision: "0" });
});
