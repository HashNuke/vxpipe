import { describe, expect, it } from "vitest";
import { parseInventory, integrationQuery } from "./inventoryApi";

export const inventoryFixture = {
  tenant: { key: "tenant-a", name: "Tenant A" }, installation_version: "0.1.0",
  directory_status: "local", can_connect_native: true, connections: [], page: null,
  fallback_items: [], local_items: [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
    connection: { type: "builtin", provider_id: "google" }, connections: [], can_connect: true }],
};

describe("integration inventory boundary", () => {
  it("reads local inventory and checks the requested tenant", () => {
    expect(parseInventory(inventoryFixture, "tenant-a").items[0].name).toBe("Google AI Studio");
    expect(() => parseInventory(inventoryFixture, "tenant-b")).toThrow();
  });
  it("never treats a missing connection projection as unconnected", () => {
    const item = { ...inventoryFixture.local_items[0], connections: undefined };
    expect(() => parseInventory({ ...inventoryFixture, local_items: [item] }, "tenant-a")).toThrow();
    expect(() => parseInventory({ ...inventoryFixture, connections: undefined }, "tenant-a")).toThrow();
  });
  it("preserves cursor tokens and omits category for global search", () => {
    const query = integrationQuery("calendar", "  all providers  ", "opaque+/=");
    expect(new URLSearchParams(query).get("q")).toBe("all providers");
    expect(new URLSearchParams(query).has("category")).toBe(false);
    expect(new URLSearchParams(query).get("cursor")).toBe("opaque+/=");
    expect(integrationQuery("connected", "", null)).toBe("category=connected");
  });
  it("keeps remote pagination separate from outage fallback", () => {
    const value = { ...inventoryFixture, directory_status: "unavailable", fallback_items: inventoryFixture.local_items, local_items: [] };
    expect(parseInventory(value, "tenant-a").pagination).toBeNull();
  });
});

it("reads tenant MCP inventory and rejects foreign or missing MCP status", () => {
  const saved = { id: "mcp-id", tenant_key: "tenant-a", endpoint: "https://mcp.example.test/mcp", server_name: "Tools",
    auth_method: "bearer", generation: 1, status: "connected", tool_count: 0, can_edit: true };
  const row = { id: "mcp-mcp-id", name: "Tools", kind: "mcp", connection: { endpoint: saved.endpoint }, connections: [], mcp_connections: [saved], can_connect: false };
  const value = { ...inventoryFixture, mcp_connections: [saved], local_items: [row] };
  expect(parseInventory(value, "tenant-a").items[0].mcpConnections[0]).toMatchObject({ id: "mcp-id", toolCount: 0, canEdit: true });
  expect(parseInventory(value, "tenant-a").mcpConnections).toHaveLength(1);
  expect(() => parseInventory({ ...value, mcp_connections: [{ ...saved, tenant_key: "tenant-b" }] }, "tenant-a")).toThrow();
  expect(() => parseInventory({ ...value, local_items: [{ ...row, mcp_connections: undefined }] }, "tenant-a")).toThrow();
});

it("preserves listed references and saved recipes independently of current directory content", () => {
  const reference = { directory_id: "public", integration_id: "calendar", entry_revision: 2, page: { scope: "tenant", category: "calendar", limit: 20 } };
  const entry = { directory_id: "public", integration_id: "calendar", revision: 1, name: "Saved calendar", endpoint: "https://old.example.test/mcp", authentication: { type: "bearer" } };
  const saved = { id: "saved", tenant_key: "tenant-a", endpoint: entry.endpoint, server_name: entry.name, auth_method: "bearer", generation: 1,
    status: "connected", tool_count: 0, can_edit: true, directory_id: "public/calendar", directory_entry: entry };
  const row = { id: "calendar", kind: "mcp", name: "New calendar", revision: 2, listing: reference,
    connection: { endpoint: "https://new.example.test/mcp", authentication: { type: "api_key", header_name: "X-Key" } },
    connections: [], mcp_connections: [saved], can_connect: false, setup_url: "https://calendar.example.test/setup" };
  const result = parseInventory({ ...inventoryFixture, local_items: [row], mcp_connections: [saved] }, "tenant-a");
  expect(result.items[0].listing).toMatchObject({ reference, entry: { name: row.name, endpoint: row.connection.endpoint, authentication: row.connection.authentication, setup_url: row.setup_url } });
  expect(result.mcpConnections[0].directoryEntry).toEqual(entry);
});

it("rejects malformed listed recipes, unsafe setup links and detached saved bindings", () => {
  const reference = { directory_id: "public", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant" } };
  const row = { id: "calendar", revision: 1, name: "Calendar", kind: "mcp", listing: reference,
    connection: { endpoint: "https://calendar.example.test/mcp", authentication: { type: "bearer" } }, connections: [], mcp_connections: [], can_connect: true };
  for (const changed of [
    { ...row, setup_url: "javascript:alert(1)" },
    { ...row, documentation_url: "https://user:password@example.test" },
    { ...row, listing: { ...reference, entry_revision: 2 } },
    { ...row, connection: { ...row.connection, authentication: { type: "unknown" } } },
  ]) expect(() => parseInventory({ ...inventoryFixture, local_items: [changed] }, "tenant-a")).toThrow();
  const saved = { id: "saved", tenant_key: "tenant-a", endpoint: row.connection.endpoint, server_name: row.name, auth_method: "bearer", generation: 1,
    status: "connected", tool_count: 0, can_edit: true, directory_id: "other/calendar", directory_entry: {
      directory_id: "public", integration_id: "calendar", revision: 1, name: row.name, ...row.connection,
    } };
  expect(() => parseInventory({ ...inventoryFixture, mcp_connections: [saved] }, "tenant-a")).toThrow();
});
