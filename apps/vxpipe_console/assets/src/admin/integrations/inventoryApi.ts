import { setupProviders, type SetupProviderId, type SetupProvider } from "../setupCatalog";
import { listedMethod, parseDirectoryEntry, parseListing, type McpDirectoryEntry, type McpListing } from "./listedMcp";

export type IntegrationConnection = {
  provider: SetupProviderId; name: string; source: "tenant" | "platform";
  status: "connected" | "invalid" | "unavailable"; credentialId: string | null; canEdit: boolean;
};
export type McpConnection = {
  id: string; endpoint: string; serverName: string; authMethod: string; generation: number;
  status: "connected" | "reconnect_required"; toolCount: number; canEdit: boolean;
  directoryEntry?: McpDirectoryEntry;
};
export type IntegrationEntry = {
  id: string; name: string; kind: "provider" | "mcp"; summary: string;
  provider?: SetupProviderId; capabilities: SetupProvider["capabilities"]; logoUrl?: string; mcpConnections: McpConnection[]; connections: IntegrationConnection[]; canConnect: boolean;
  listing?: McpListing;
};
export type IntegrationPagination = {
  total: number; start: number; end: number; next: string | null; previous: string | null;
};
export type IntegrationInventory = {
  tenant: { key: string; name: string } | null; version: string;
  status: "local" | "available" | "unavailable"; items: IntegrationEntry[];
  mcpConnections: McpConnection[]; connections: IntegrationConnection[]; pagination: IntegrationPagination | null;
};
export type IntegrationCategory = { id: string; name: string; count: number };

const object = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const invalid = () => new Error("Integration inventory is unavailable. Retry to load current connections.");
const text = (value: unknown, max = 2048): value is string => typeof value === "string" && value.length <= max;
const integer = (value: unknown): value is number => Number.isSafeInteger(value) && Number(value) >= 0;
const cursor = (value: unknown): value is string | null => value === null || (text(value) && value.length > 0);
const provider = (value: unknown): value is SetupProviderId => setupProviders.some(item => item.id === value);

function connection(value: unknown): IntegrationConnection {
  if (!object(value) || !provider(value.provider) || !text(value.name, 128) ||
    !["tenant", "platform"].includes(String(value.source)) ||
    !["connected", "invalid", "unavailable"].includes(String(value.status)) ||
    !(value.credential_id === null || text(value.credential_id, 128)) || typeof value.can_edit !== "boolean") throw invalid();
  return { provider: value.provider, name: value.name, source: value.source as IntegrationConnection["source"],
    status: value.status as IntegrationConnection["status"], credentialId: value.credential_id as string | null, canEdit: value.can_edit };
}

function mcpConnection(value: unknown, tenantKey: string | null): McpConnection {
  if (!object(value) || tenantKey === null || value.tenant_key !== tenantKey ||
    !text(value.id, 128) || !value.id || !text(value.endpoint) || !value.endpoint.startsWith("https://") ||
    !text(value.server_name, 200) || !text(value.auth_method, 32) ||
    !integer(value.generation) || value.generation < 1 || !integer(value.tool_count) ||
    !["connected", "reconnect_required"].includes(String(value.status)) || typeof value.can_edit !== "boolean") throw invalid();
  const directoryEntry = value.directory_entry == null ? undefined : parseDirectoryEntry(value.directory_entry);
  if (directoryEntry && (value.directory_id !== `${directoryEntry.directory_id}/${directoryEntry.integration_id}` ||
    value.endpoint !== directoryEntry.endpoint || value.server_name !== directoryEntry.name ||
    value.auth_method !== (directoryEntry.authentication.type === "oauth2" ? "oauth" : listedMethod(directoryEntry)))) throw invalid();
  return { id: value.id, endpoint: value.endpoint, serverName: value.server_name, authMethod: value.auth_method, directoryEntry,
    generation: value.generation, status: value.status as McpConnection["status"], toolCount: value.tool_count, canEdit: value.can_edit };
}

function entry(value: unknown, tenantKey: string | null): IntegrationEntry {
  if (!object(value) || !text(value.id, 128) || !text(value.name, 200) || !["provider", "mcp"].includes(String(value.kind)) ||
    !Array.isArray(value.connections) || typeof value.can_connect !== "boolean" || !object(value.connection)) throw invalid();
  if (value.kind === "provider" && !provider(value.connection.provider_id)) throw invalid();
  const capabilities = value.kind === "provider" ? value.capabilities ?? [] : [];
  if (!Array.isArray(capabilities) || capabilities.length > 5 ||
    !capabilities.every(item => ["stt", "llm", "tts", "sts", "telephony"].includes(item))) throw invalid();
  const mcps = value.mcp_connections ?? (value.kind === "provider" ? [] : undefined);
  if (!Array.isArray(mcps)) throw invalid();
  return { id: value.id, name: value.name, mcpConnections: mcps.map(item => mcpConnection(item, tenantKey)), kind: value.kind as IntegrationEntry["kind"],
    provider: value.kind === "provider" ? value.connection.provider_id as SetupProviderId : undefined,
    capabilities: capabilities.map(value => value === "sts" ? "s2s" : value) as SetupProvider["capabilities"],
    summary: text(value.summary, 200) ? value.summary : "",
    logoUrl: text(value.logo_url) && value.logo_url.startsWith("https://") ? value.logo_url : undefined,
    connections: value.connections.map(connection), canConnect: value.can_connect,
    listing: value.kind === "mcp" ? parseListing(value) : undefined };
}

export function parseInventory(value: unknown, tenantKey: string | null): IntegrationInventory {
  if (!object(value) || !Array.isArray(value.connections) || value.connections.length > 1500 ||
    !text(value.installation_version, 128) || !["local", "available", "unavailable"].includes(String(value.directory_status))) throw invalid();
  const tenant = value.tenant;
  if (tenantKey === null ? tenant !== null : !object(tenant) || tenant.key !== tenantKey || !text(tenant.name, 200)) throw invalid();
  let pagination: IntegrationPagination | null = null;
  let items: unknown;
  if (value.directory_status === "available") {
    if (!object(value.page) || !object(value.page.pagination)) throw invalid();
    const page = value.page.pagination;
    if (![page.total_items, page.start_index, page.end_index].every(integer) || !cursor(page.next_cursor) || !cursor(page.previous_cursor)) throw invalid();
    pagination = { total: page.total_items as number, start: page.start_index as number, end: page.end_index as number, next: page.next_cursor, previous: page.previous_cursor };
    items = value.page.items;
  } else {
    items = value.directory_status === "local" ? value.local_items : value.fallback_items;
  }
  if (!Array.isArray(items) || items.length > 1500) throw invalid();
  const parsed = items.map(item => entry(item, tenantKey));
  const mcps = value.mcp_connections ?? (parsed.every(item => item.kind === "provider") ? [] : undefined);
  if (!Array.isArray(mcps) || mcps.length > 1500) throw invalid();
  const mcpConnections = mcps.map(item => mcpConnection(item, tenantKey));
  if (new Set(mcpConnections.map(item => item.id)).size !== mcpConnections.length) throw invalid();
  if (new Set(parsed.map(item => item.id)).size !== parsed.length) throw invalid();
  return { tenant: tenant as IntegrationInventory["tenant"], version: value.installation_version,
    status: value.directory_status as IntegrationInventory["status"], items: parsed,
    connections: value.connections.map(connection), mcpConnections, pagination };
}

export function integrationQuery(category: string, search: string, pageCursor: string | null) {
  const params = new URLSearchParams();
  const query = search.trim();
  if (query) params.set("q", query); else params.set("category", category);
  if (pageCursor && category !== "connected") params.set("cursor", pageCursor);
  return params.toString();
}

export function parseCategories(value: unknown): IntegrationCategory[] {
  if (!object(value) || !Array.isArray(value.categories) || value.categories.length > 1000) throw invalid();
  return value.categories.map(item => {
    if (!object(item) || !text(item.id, 64) || !text(item.name, 64) || !integer(item.integration_count)) throw invalid();
    return { id: item.id, name: item.name, count: item.integration_count };
  });
}
