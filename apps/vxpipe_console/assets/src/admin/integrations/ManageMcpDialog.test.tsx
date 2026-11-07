import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";
import type { McpConnection } from "./inventoryApi";
afterEach(cleanup);
const connection: McpConnection = { id: "saved-id", endpoint: "https://mcp.example.test/mcp", serverName: "Tools server", authMethod: "bearer", generation: 3, status: "connected", toolCount: 1, canEdit: true };
const props = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn(), connection };
function fixture() {
  return vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "DELETE") return Response.json({ connection: { id: "saved-id", generation: 4, status: "revoked" } });
    return Response.json({ connection: { id: "saved-id", generation: init?.method === "PATCH" ? 4 : 3, tools: [{ name: "list_events" }] } });
  });
}

test("saved credentials are not loaded; retest preserves them and disconnect uses the latest generation", async () => {
  const fetchImpl = fixture();
  render(<CustomMcpDialog {...props} fetchImpl={fetchImpl} />);
  expect(await screen.findByText("Credentials saved. Values are never displayed.")).toBeInTheDocument();
  expect(screen.queryByLabelText("Bearer token")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Test connection" }));
  await waitFor(() => expect(fetchImpl.mock.calls.some(call => call[1]?.method === "PATCH")).toBe(true));
  const patch = fetchImpl.mock.calls.find(call => call[1]?.method === "PATCH");
  expect(JSON.parse(String(patch?.[1]?.body))).toEqual({ endpoint: connection.endpoint, auth_method: "bearer", generation: 3 });
  await waitFor(() => expect(screen.getByRole("button", { name: "Disconnect" })).toBeEnabled());
  fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));
  await waitFor(() => expect(fetchImpl.mock.calls.some(call => call[1]?.method === "DELETE")).toBe(true));
  expect(JSON.parse(String(fetchImpl.mock.calls.find(call => call[1]?.method === "DELETE")?.[1]?.body))).toEqual({ generation: 4 });
});

test("Tools tab reads cached catalog and read-only access has no mutation controls", async () => {
  render(<CustomMcpDialog {...props} connection={{ ...connection, canEdit: false }} fetchImpl={fixture()} />);
  const tools = screen.getByRole("tab", { name: "Tools" });
  fireEvent.mouseDown(tools, { button: 0, ctrlKey: false });
  expect(await screen.findByText("list_events")).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Disconnect" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Refresh tools" })).not.toBeInTheDocument();
});

test("switching to Tools does not dismiss when pointer release lands outside the resized panel", async () => {
  const onClose = vi.fn();
  render(<CustomMcpDialog {...props} onClose={onClose} fetchImpl={fixture()} />);
  const tools = screen.getByRole("tab", { name: "Tools" });
  const backdrop = screen.getByRole("dialog").parentElement!;
  const pointer = { pointerId: 1, isPrimary: true, button: 0 };
  fireEvent.pointerDown(tools, pointer);
  fireEvent.mouseDown(tools, { button: 0, ctrlKey: false });
  expect(await screen.findByText("list_events")).toBeInTheDocument();
  fireEvent.pointerUp(backdrop, pointer);
  fireEvent.click(backdrop);
  expect(onClose).not.toHaveBeenCalled();
  expect(screen.getByRole("tab", { name: "Tools" })).toHaveAttribute("aria-selected", "true");
});

test("stale saves retain the dialog and explain recovery", async () => {
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => init?.method === "PATCH" ? new Response("", { status: 409 }) : Response.json({ connection: { id: "saved-id", generation: 3, tools: [] } }));
  render(<CustomMcpDialog {...props} fetchImpl={fetchImpl} />);
  fireEvent.click(screen.getByRole("button", { name: "Test connection" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("changed since you opened");
  expect(screen.getByRole("dialog")).toBeInTheDocument();
});

test("refresh tools uses saved credentials and endpoint even while an unsaved edit is invalid", async () => {
  const fetchImpl = fixture();
  render(<CustomMcpDialog {...props} fetchImpl={fetchImpl} />);
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: "https://" } });
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Tools" }), { button: 0, ctrlKey: false });
  fireEvent.click(screen.getByRole("button", { name: "Refresh tools" }));
  await waitFor(() => expect(fetchImpl.mock.calls.some(call => call[1]?.method === "PATCH")).toBe(true));
  const patch = fetchImpl.mock.calls.find(call => call[1]?.method === "PATCH");
  expect(JSON.parse(String(patch?.[1]?.body))).toEqual({ generation: 3, refresh_tools: true });
});


test("saving a discovered anonymous endpoint retains its authentication method", async () => {
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: {
      ...JSON.parse(String(init?.body)), outcome: "anonymous", suggested_method: "none",
    } });
    return Response.json({ connection: { id: "saved-id", generation: init?.method === "PATCH" ? 4 : 3, tools: [] } });
  });
  render(<CustomMcpDialog {...props} fetchImpl={fetchImpl} />);
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: "https://anonymous.example.test/mcp" } });
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("none"));
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "Test connection" })).toBeEnabled());
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("none");
});
