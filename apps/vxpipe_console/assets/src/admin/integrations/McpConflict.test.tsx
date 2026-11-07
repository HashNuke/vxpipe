import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";

afterEach(cleanup);
const endpoint = "https://mcp.example.test/mcp";
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };
const enter = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });
const record = { id: "retained", tenant_key: "tenant-a", endpoint, server_name: "Saved tools", auth_method: "bearer", generation: 7, status: "revoked", tool_count: 0, can_edit: true };
function fixture(kind = "mcp_reconnect_required", changed = {}) {
  return vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: { endpoint, revision: JSON.parse(String(init?.body)).revision, outcome: "unknown", suggested_method: null } });
    if (init?.method === "POST") return Response.json({ error: { code: kind, connection_id: "retained", ...(kind === "mcp_reconnect_required" ? { generation: 7 } : {}) } }, { status: 409 });
    return Response.json({ connection: { ...record, ...(kind === "mcp_connection_exists" ? { status: "connected" } : {}), ...changed } });
  });
}
function submit() {
  enter("MCP server URL", endpoint); enter("Authentication Type", "bearer"); enter("Bearer token", "synthetic-secret");
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
}

test("a retained conflict requires explicit review and fresh generation-bound metadata before opening reconnect", async () => {
  const fetchImpl = fixture(), onOpenConnection = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} onOpenConnection={onOpenConnection} />);
  submit();
  const review = await screen.findByRole("button", { name: "Review reconnect" });
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-discovery", expect.objectContaining({ method: "POST" })));
  expect(onOpenConnection).not.toHaveBeenCalled();
  expect(fetchImpl.mock.calls.filter(([url, init]) => init?.method === "POST" && String(url) !== "/api/tenants/tenant-a/mcp-discovery")).toHaveLength(1);
  fireEvent.click(review);
  await waitFor(() => expect(onOpenConnection).toHaveBeenCalledOnce());
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-connections/retained?retained_generation=7", expect.objectContaining({ credentials: "same-origin" }));
  expect(onOpenConnection.mock.calls[0][0]).toMatchObject({ id: "retained", generation: 7, status: "revoked", endpoint, canEdit: true });
  expect(screen.getByLabelText("Bearer token")).toHaveValue("");
  expect(JSON.stringify(onOpenConnection.mock.calls[0])).not.toContain("synthetic-secret");
});

test.each(["url", "method"])("changing %s invalidates a retained reconnect proposal", async change => {
  const onOpenConnection = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fixture()} onOpenConnection={onOpenConnection} />);
  submit();
  await screen.findByRole("button", { name: "Review reconnect" });
  if (change === "url") enter("MCP server URL", "https://other.example.test/mcp");
  else enter("Authentication Type", "basic");
  expect(screen.queryByRole("button", { name: "Review reconnect" })).not.toBeInTheDocument();
  expect(onOpenConnection).not.toHaveBeenCalled();
});

test.each([{ generation: 8 }, { tenant_key: "other-tenant" }, { id: "other" }, { status: "connected" }, { can_edit: false }])("rejects stale or unrelated retained metadata: %j", async changed => {
  const onOpenConnection = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fixture("mcp_reconnect_required", changed)} onOpenConnection={onOpenConnection} />);
  submit(); fireEvent.click(await screen.findByRole("button", { name: "Review reconnect" }));
  await screen.findByText(/Could not load this connection/);
  expect(onOpenConnection).not.toHaveBeenCalled();
});

test("a connected duplicate opens current management and never offers reconnect", async () => {
  const fetchImpl = fixture("mcp_connection_exists"), onOpenConnection = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} onOpenConnection={onOpenConnection} />);
  submit(); fireEvent.click(await screen.findByRole("button", { name: "Manage existing connection" }));
  await waitFor(() => expect(onOpenConnection).toHaveBeenCalledOnce());
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-connections/retained", expect.objectContaining({ credentials: "same-origin" }));
  expect(screen.queryByRole("button", { name: "Review reconnect" })).not.toBeInTheDocument();
  expect(onOpenConnection.mock.calls[0][0]).toMatchObject({ status: "connected", id: "retained" });
});

test("a connected duplicate may open read-only management after write permission changes", async () => {
  const onOpenConnection = vi.fn();
  render(<CustomMcpDialog {...defaults} fetchImpl={fixture("mcp_connection_exists", { can_edit: false })} onOpenConnection={onOpenConnection} />);
  submit(); fireEvent.click(await screen.findByRole("button", { name: "Manage existing connection" }));
  await waitFor(() => expect(onOpenConnection).toHaveBeenCalledOnce());
  expect(onOpenConnection.mock.calls[0][0]).toMatchObject({ status: "connected", canEdit: false });
});

test("closing during a retained lookup ignores its late response", async () => {
  let release!: (response: Response) => void;
  const delayed = new Promise<Response>(resolve => { release = resolve; });
  const fresh = fixture(); const onOpenConnection = vi.fn();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("retained_generation") ? delayed : fresh(url, init));
  const view = render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} onOpenConnection={onOpenConnection} />);
  submit(); fireEvent.click(await screen.findByRole("button", { name: "Review reconnect" }));
  view.unmount(); release(Response.json({ connection: record }));
  await delayed;
  expect(onOpenConnection).not.toHaveBeenCalled();
});

test("a failed metadata read can be retried without resubmitting credentials", async () => {
  const fresh = fixture(); const onOpenConnection = vi.fn(); let failed = true;
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("retained_generation") && failed ? new Response(null, { status: 503 }) : fresh(url, init));
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} onOpenConnection={onOpenConnection} />);
  submit(); fireEvent.click(await screen.findByRole("button", { name: "Review reconnect" }));
  await screen.findByText(/Could not load this connection/);
  failed = false; fireEvent.click(screen.getByRole("button", { name: "Review reconnect" }));
  await waitFor(() => expect(onOpenConnection).toHaveBeenCalledOnce());
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-discovery", expect.objectContaining({ method: "POST" })));
  expect(fetchImpl.mock.calls.filter(([url, init]) => init?.method === "POST" && String(url) !== "/api/tenants/tenant-a/mcp-discovery")).toHaveLength(1);
});
