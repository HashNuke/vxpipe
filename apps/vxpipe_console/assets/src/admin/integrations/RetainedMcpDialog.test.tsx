import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";

afterEach(cleanup);
const endpoint = "https://mcp.example.test/mcp";
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };
const connection = { id: "retained", endpoint, serverName: "Saved tools", authMethod: "bearer", generation: 7, status: "revoked" as const, toolCount: 0, canEdit: true };
const enter = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });

test("read-only retained inspection cannot offer a reconnect mutation", () => {
  const fetchImpl = vi.fn();
  render(<CustomMcpDialog {...defaults} connection={{ ...connection, canEdit: false }} fetchImpl={fetchImpl} />);
  expect(screen.queryByRole("button", { name: "Reconnect" })).not.toBeInTheDocument();
  expect(fetchImpl).not.toHaveBeenCalled();
});

test("retained static setup requires fresh credentials and explicit reconnect to the existing identity", async () => {
  const fetchImpl = vi.fn<typeof fetch>(async () => Response.json({ connection: { id: "retained", generation: 8 } }));
  const onConnected = vi.fn();
  render(<CustomMcpDialog {...defaults} connection={connection} fetchImpl={fetchImpl} onConnected={onConnected} />);
  expect(screen.getByLabelText("Bearer token")).toHaveValue("");
  expect(screen.getByLabelText("MCP server URL")).toBeDisabled();
  expect(screen.queryByRole("button", { name: "Disconnect" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Test connection" })).not.toBeInTheDocument();
  expect(screen.queryByRole("tab", { name: "Tools" })).not.toBeInTheDocument();
  expect(fetchImpl).not.toHaveBeenCalled();
  enter("Bearer token", "synthetic-new");
  fireEvent.click(screen.getByRole("button", { name: "Reconnect" }));
  await waitFor(() => expect(onConnected).toHaveBeenCalledOnce());
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-connections/retained/reconnect", expect.objectContaining({ method: "POST" }));
  expect(JSON.parse(String(fetchImpl.mock.calls[0][1]?.body))).toEqual({ endpoint, auth_method: "bearer", generation: 7, credentials: { token: "synthetic-new" } });
});

test.each([false, true])("retained OAuth uses the existing browser or machine reconnect operation (machine %s)", async machine => {
  const onAuthorize = vi.fn(), onConnected = vi.fn();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: { endpoint, revision: JSON.parse(String(init?.body)).revision,
      outcome: "oauth", suggested_method: "dcr", supported_grants: ["authorization_code", "client_credentials"],
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      resource: { resource: endpoint }, oauth: { issuer: "https://auth.example.test", registration_endpoint: "https://auth.example.test/register",
        authorization_endpoint: "https://auth.example.test/authorize", token_endpoint: "https://auth.example.test/token", token_endpoint_auth_methods_supported: ["client_secret_basic"] } } });
    return machine ? Response.json({ connection: { id: "retained", generation: 8 } }) : Response.json({ authorization_url: "https://auth.example.test/authorize", connection_id: "retained", attempt_id: "fresh" });
  });
  render(<CustomMcpDialog {...defaults} connection={{ ...connection, authMethod: "oauth" }} fetchImpl={fetchImpl} onAuthorize={onAuthorize} onConnected={onConnected} />);
  await screen.findByText("OAuth settings discovered.");
  if (machine) {
    enter("Authentication Type", "own_client"); enter("Grant type", "client_credentials"); enter("Client ID", "client"); enter("Client secret", "synthetic-new");
  }
  fireEvent.click(screen.getByRole("button", { name: "Reconnect" }));
  await waitFor(() => expect(machine ? onConnected : onAuthorize).toHaveBeenCalledOnce());
  const request = fetchImpl.mock.calls.find(([url]) => !String(url).endsWith("/mcp-discovery"));
  expect(String(request?.[0])).toBe(`/api/tenants/tenant-a/mcp-connections/retained/${machine ? "reconnect" : "oauth"}`);
  expect(request?.[1]?.method).toBe("POST");
  expect(JSON.parse(String(request?.[1]?.body))).toHaveProperty("generation", 7);
  if (!machine) expect(onAuthorize.mock.calls[0][1]).toMatchObject({ generation: 7, endpoint });
});
