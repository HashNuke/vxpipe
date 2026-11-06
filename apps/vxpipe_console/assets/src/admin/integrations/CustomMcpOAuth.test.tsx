import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";

afterEach(cleanup);
const endpoint = "https://mcp.example.test/mcp";
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };
const handoff = { authorization_url: "https://auth.example.test/authorize?state=opaque", attempt_id: "attempt-id", connection_id: "connection-id" };
function fixture(machine = false, authorizationUrl = handoff.authorization_url) {
  return vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: {
      ...body, outcome: "oauth", suggested_method: machine ? "own_client" : "cimd", supported_grants: [machine ? "client_credentials" : "authorization_code"],
      issuers: ["https://auth.example.test"], resource: { scopes_supported: ["tools.read"] },
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      oauth: { issuer: "https://auth.example.test", token_endpoint: "https://auth.example.test/token", authorization_endpoint: "https://auth.example.test/authorize",
        registration_endpoint: "https://auth.example.test/register", client_id_metadata_document_supported: true,
        token_endpoint_auth_methods_supported: machine ? ["client_secret_basic"] : ["none", "client_secret_basic"] },
    } });
    if (String(url).endsWith("/mcp-oauth")) return Response.json({ ...handoff, authorization_url: authorizationUrl }, { status: 201 });
    return Response.json({ connection: { id: "saved", generation: 1 } }, { status: 201 });
  });
}
const enter = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });

test.each(["cimd", "dcr"])("%s discovery and Connect use managed browser OAuth without manual credentials", async method => {
  const fetchImpl = fixture();
  const authorize = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} onAuthorize={authorize} returnTo="/t/tenant-a/services/search?q=tools" />);
  enter("MCP server URL", endpoint);
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("cimd"));
  if (method === "dcr") { enter("Authentication Type", "dcr"); enter("Initial registration token", "synthetic-initial-token"); }
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Additional parameters" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(authorize).toHaveBeenCalledOnce());
  const call = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-oauth"));
  expect(JSON.parse(String(call?.[1]?.body))).toEqual({ endpoint, revision: "1", auth_method: method,
    return_to: "/t/tenant-a/services/search?q=tools", ...(method === "dcr" ? { initial_access_token: "synthetic-initial-token" } : {}) });
  expect(authorize.mock.calls[0][0]).toMatchObject({ authorizationUrl: handoff.authorization_url, attemptId: handoff.attempt_id, connectionId: handoff.connection_id });
});

test("machine grants connect through the existing connection route without browser consent fields", async () => {
  const fetchImpl = fixture(true);
  const connected = vi.fn();
  const authorize = vi.fn();
  render(<CustomMcpDialog {...defaults} onConnected={connected} fetchImpl={fetchImpl} onAuthorize={authorize} />);
  enter("MCP server URL", endpoint);
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("own_client"));
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  enter("Client ID", "registered"); enter("Client secret", "synthetic-secret");
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(connected).toHaveBeenCalledOnce());
  const call = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-connections"));
  const body = JSON.parse(String(call?.[1]?.body));
  expect(body).toMatchObject({ endpoint, revision: "1", auth_method: "own_client", credentials: { grant_type: "client_credentials", client_id: "registered", client_secret: "synthetic-secret" } });
  expect(body.credentials).not.toHaveProperty("authorization_endpoint");
  expect(body.credentials).not.toHaveProperty("authorization_parameters");
  expect(authorize).not.toHaveBeenCalled();
});

test("an invalid authorization redirect stays in the form with a recoverable error", async () => {
  const authorize = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fixture(false, "javascript:alert(1)")} onAuthorize={authorize} />);
  enter("MCP server URL", endpoint);
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("cimd"));
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByRole("alert")).toBeVisible();
  expect(authorize).not.toHaveBeenCalled();
  expect(screen.getByLabelText("MCP server URL")).toHaveValue(endpoint);
});

test("saved OAuth management retests current credentials and reconnects with its actual registration method", async () => {
  const authorize = vi.fn();
  const fresh = fixture();
  const connection = { id: "saved-oauth", endpoint, serverName: "Saved tools", authMethod: "oauth", generation: 7, status: "connected" as const, toolCount: 0, canEdit: true };
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/saved-oauth/oauth")) return Response.json(handoff, { status: 201 });
    if (String(url).endsWith("/saved-oauth")) return Response.json({ connection: { ...connection, tools: [], oauth: { registration_method: "dcr", grant_type: "authorization_code", auth_method: "none" } } });
    return fresh(url, init);
  });
  render(<CustomMcpDialog {...defaults} connection={connection} fetchImpl={fetchImpl} onAuthorize={authorize} />);
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("dcr"));
  expect(screen.queryByLabelText("Initial registration token")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Test connection" }));
  await waitFor(() => expect(fetchImpl.mock.calls.some(([, init]) => init?.method === "PATCH")).toBe(true));
  const patch = fetchImpl.mock.calls.find(([, init]) => init?.method === "PATCH");
  expect(JSON.parse(String(patch?.[1]?.body))).toEqual({ generation: 7, refresh_tools: true });
  await waitFor(() => expect(screen.getByLabelText("Replace credentials")).toBeEnabled());
  fireEvent.click(screen.getByLabelText("Replace credentials"));
  await screen.findByText("OAuth settings discovered.");
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("dcr");
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() => expect(authorize).toHaveBeenCalledOnce());
  const post = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/saved-oauth/oauth"));
  expect(JSON.parse(String(post?.[1]?.body))).toEqual({ endpoint, revision: "0", auth_method: "dcr", generation: 7 });
});

test("partial discovery explains missing settings and does not imply OAuth readiness", async () => {
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => Response.json({ discovery: {
    ...JSON.parse(String(init?.body)), outcome: "partial", suggested_method: null, issuers: ["https://auth.example.test"],
  } }));
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} />);
  enter("MCP server URL", endpoint);
  expect(await screen.findByText(/Some OAuth settings could not be discovered/)).toBeVisible();
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("");
  expect(screen.getByRole("button", { name: "Retry discovery" })).toBeEnabled();
});

test("browser OAuth explains the saved endpoint constraint before attempting an unsupported reconnect", async () => {
  const fresh = fixture();
  const connection = { id: "saved", endpoint, serverName: "Saved tools", authMethod: "oauth", generation: 7, status: "connected" as const, toolCount: 0, canEdit: true };
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/saved") && !init?.method) return Response.json({ connection: { ...connection, tools: [], oauth: { registration_method: "cimd", grant_type: "authorization_code", auth_method: "none" } } });
    if (String(url).endsWith("/saved/oauth")) return Response.json({ error: { code: "invalid_mcp_oauth_reconnect" } }, { status: 422 });
    return fresh(url, init);
  });
  render(<CustomMcpDialog {...defaults} connection={connection} fetchImpl={fetchImpl} />);
  enter("MCP server URL", "https://other.example.test/mcp");
  await screen.findByText("OAuth settings discovered.");
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("To use a different server URL with OAuth, connect it as a new MCP.");
  expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith("/saved/oauth"))).toBe(false);
});
