import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";

afterEach(cleanup);
const reference = { directory_id: "public", integration_id: "calendar", entry_revision: 1, page: { category: "calendar", scope: "tenant", limit: 20 } };
const entry = { directory_id: "public", integration_id: "calendar", revision: 1, name: "Calendar tools", endpoint: "https://calendar.example.test/mcp",
  authentication: { type: "api_key" as const, header_name: "X-Calendar-Key" },
  setup_notes: "Create a key in <b>Calendar settings</b>.", setup_url: "https://calendar.example.test/settings", documentation_url: "https://calendar.example.test/docs" };
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };

test("listed API-key Connect locks the recipe and sends only its reference and secret value", async () => {
  const onConnected = vi.fn();
  const fetchImpl = vi.fn<(url: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(async () => Response.json({ connection: { id: "new-id", generation: 1 } }, { status: 201 }));
  render(<CustomMcpDialog {...defaults} onConnected={onConnected} fetchImpl={fetchImpl} listing={{ reference, entry }} />);
  expect(screen.getByRole("dialog", { name: "Connect Calendar tools" })).toBeInTheDocument();
  expect(screen.getByText(entry.endpoint)).toBeInTheDocument();
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Authentication Type")).not.toBeInTheDocument();
  expect(screen.queryByText("Additional MCP request headers")).not.toBeInTheDocument();
  expect(screen.getByText(entry.setup_notes)).toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Setup" })).toHaveAttribute("href", entry.setup_url);
  expect(screen.getByRole("link", { name: "Documentation" })).toHaveAttribute("rel", "noopener noreferrer");
  const key = screen.getByLabelText("X-Calendar-Key");
  expect(key).toHaveAttribute("type", "password");
  fireEvent.change(key, { target: { value: "synthetic-key" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(onConnected).toHaveBeenCalledOnce());
  expect(fetchImpl).toHaveBeenCalledOnce();
  const [url, init] = fetchImpl.mock.calls[0];
  expect(url).toBe("/api/tenants/tenant-a/mcp-connections");
  expect(init?.method).toBe("POST");
  expect(JSON.parse(String(init?.body))).toEqual({ listing: reference, credentials: { headers: [{ value: "synthetic-key" }] } });
});

test("saved listed replacement stays locked and uses the saved connection route without discovery", async () => {
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => Response.json({ connection: {
    id: "saved-id", generation: init?.method === "PATCH" ? 4 : 3, tools: [], directory_entry: entry,
  } }));
  const saved = { id: "saved-id", endpoint: entry.endpoint, serverName: entry.name, authMethod: "headers", generation: 3,
    status: "connected" as const, toolCount: 0, canEdit: true, directoryEntry: entry };
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} connection={saved} />);
  expect(await screen.findByText("Credentials saved. Values are never displayed.")).toBeInTheDocument();
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
  fireEvent.click(screen.getByLabelText("Replace credentials"));
  fireEvent.change(screen.getByLabelText("X-Calendar-Key"), { target: { value: "replacement" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await waitFor(() => expect(fetchImpl.mock.calls.some(call => call[1]?.method === "PATCH")).toBe(true));
  const [url, init] = fetchImpl.mock.calls.find(call => call[1]?.method === "PATCH")!;
  expect(url).toBe("/api/tenants/tenant-a/mcp-connections/saved-id");
  expect(JSON.parse(String(init?.body))).toEqual({ generation: 3, credentials: { headers: [{ value: "replacement" }] } });
  expect(fetchImpl.mock.calls.some(call => String(call[0]).includes("mcp-discovery"))).toBe(false);
});

test("a changed or unavailable listing keeps the dialog and directs the user to browse again", async () => {
  const onConnected = vi.fn();
  const fetchImpl = vi.fn(async () => Response.json({ error: { code: "mcp_listing_unavailable" } }, { status: 503 }));
  render(<CustomMcpDialog {...defaults} onConnected={onConnected} fetchImpl={fetchImpl} listing={{ reference, entry: { ...entry, authentication: { type: "none" } } }} />);
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("directory entry changed or is unavailable");
  expect(onConnected).not.toHaveBeenCalled();
});
