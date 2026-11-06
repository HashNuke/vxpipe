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
