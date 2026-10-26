import { setupProviders } from "../setupCatalog";
import type { Connection, Preset } from "./fixtures";

/** Proposed hosted API v1 contract. This preview never performs a network request. */
export type DirectoryAuthentication =
  | { type: "oauth2"; registration: "discover" | "cimd" | "dcr" | "preregistered"; scopes?: string[] }
  | { type: "none" | "bearer" | "basic" }
  | { type: "api_key"; header_name: string };
export type RemoteCategory = { id: string; name: string; order: number; integration_count: number };
type RemoteIntegrationInfo = {
  id: string;
  minimum_vxpipe_version?: string;
  maximum_vxpipe_version_exclusive?: string;
  revision: number;
  name: string;
  summary?: string;
  logo_url?: string;
  category_ids: string[];
  documentation_url?: string;
  setup_url?: string;
  availability: "available" | "preview" | "retired";
  setup_notes?: string;
};
export type RemoteMcpIntegration = RemoteIntegrationInfo & {
  kind: "mcp";
  connection: {
    type: "mcp";
    transport: "streamable_http";
    endpoint: string;
    authentication: DirectoryAuthentication;
  };
};
export type RemoteProviderIntegration = RemoteIntegrationInfo & { documentation_url: string; kind: "provider"; connection: { type: "builtin"; provider_id: string } };
export type RemoteIntegration = RemoteMcpIntegration | RemoteProviderIntegration;
export function isMcpIntegration(entry: RemoteIntegration): entry is RemoteMcpIntegration { return entry.kind === "mcp"; }
export type RemoteDirectoryFixture = {
  schema_version: 1;
  directory_id: string;
  revision: string;
  categories: RemoteCategory[];
  integrations: RemoteIntegration[];
};
export type DirectoryLoadState = "ready" | "loading" | "unavailable" | "stale";
export type ConnectionLoadState = "ready" | "loading" | "unavailable";

export function directoryPreset(entry: RemoteMcpIntegration, directoryId: string): Preset {
  const auth = entry.connection.authentication;
  return {
    id: entry.id, directoryId, directoryRevision: entry.revision,
    name: entry.name, description: entry.summary ?? "", logo: entry.logo_url,
    category: entry.category_ids[0], categories: entry.category_ids,
    endpoint: entry.connection.endpoint,
    auth: auth.type === "oauth2" ? auth.registration === "discover" ? "auto" : auth.registration === "preregistered" ? "custom" : auth.registration
      : auth.type === "none" ? "none" : "custom",
    customAuth: auth.type === "oauth2" ? "oauth" : auth.type === "api_key" ? "headers" : auth.type === "basic" ? "basic" : "bearer",
    scopes: auth.type === "oauth2" ? auth.scopes?.join(" ") : undefined,
    headerName: auth.type === "api_key" ? auth.header_name : undefined,
    icon: entry.category_ids.includes("calendar") ? "calendar" : entry.category_ids.includes("crm") ? "crm" : "custom",
    docs: entry.documentation_url, preview: entry.availability === "preview", retired: entry.availability === "retired", setupNotes: entry.setup_notes, setupUrl: entry.setup_url,
  };
}

/** Storybook server-side dataset. Never a complete-catalog API response. */
export const remoteCatalog: RemoteDirectoryFixture = {
  schema_version: 1,
  directory_id: "vxpipe-public",
  revision: "2026-10-25.1",
  categories: [
    { id: "calendar", name: "Calendar", order: 10, integration_count: 3 },
    { id: "crm", name: "CRM", order: 20, integration_count: 1 },
    { id: "office", name: "Office suite", order: 30, integration_count: 2 },
  ],
  integrations: [
    {
      id: "calcom", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Cal.com", summary: "Availability and bookings", category_ids: ["calendar"], availability: "available",
      documentation_url: "https://cal.com/docs/mcp-server",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://mcp.cal.com/mcp", authentication: { type: "oauth2", registration: "discover" } },
    },
    {
      id: "google-calendar", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Google Calendar", summary: "Calendars and events", category_ids: ["calendar"], availability: "preview",
      documentation_url: "https://developers.google.com/workspace/calendar/api/guides/configure-mcp-server",
      setup_notes: "Use an OAuth client from your Google Cloud project. Workspace Developer Preview access is required.",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://calendarmcp.googleapis.com/mcp/v1", authentication: { type: "oauth2", registration: "preregistered" } },
    },
    {
      id: "google-sheets", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Google Sheets", summary: "Spreadsheets and records", category_ids: ["office"], availability: "preview",
      documentation_url: "https://developers.google.com/workspace/sheets/api/guides/configure-mcp-server",
      setup_notes: "Use an OAuth client from your Google Cloud project. Workspace Developer Preview access is required.",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://sheetsmcp.googleapis.com/mcp/v1", authentication: { type: "oauth2", registration: "preregistered" } },
    },
    {
      id: "hubspot", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "HubSpot", summary: "Contacts and customer records", category_ids: ["crm"], availability: "available",
      documentation_url: "https://developers.hubspot.com/docs/apps/developer-platform/build-apps/integrate-with-the-remote-hubspot-mcp-server",
      setup_notes: "Create an MCP connector in HubSpot, then enter its client ID and secret.",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://mcp.hubspot.com", authentication: { type: "oauth2", registration: "preregistered" } },
    },
    {
      id: "calendly", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Calendly", summary: "Scheduling and meetings", category_ids: ["calendar"], availability: "available",
      documentation_url: "https://developer.calendly.com/docs/mcp/calendly-mcp-server",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://mcp.calendly.com", authentication: { type: "oauth2", registration: "dcr" } },
    },
    {
      id: "google-docs", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Google Docs", summary: "Documents and content", category_ids: ["office"], availability: "preview",
      documentation_url: "https://developers.google.com/workspace/docs/api/guides/configure-mcp-server",
      setup_notes: "Use an OAuth client from your Google Cloud project. Workspace Developer Preview access is required.",
      connection: { type: "mcp", transport: "streamable_http", endpoint: "https://docsmcp.googleapis.com/mcp/v1", authentication: { type: "oauth2", registration: "preregistered" } },
    },
  ],
};
export const expandedRemoteCatalog: RemoteDirectoryFixture = {
  ...remoteCatalog,
  categories: [...remoteCatalog.categories, { id: "knowledge", name: "Knowledge base", order: 40, integration_count: 1 }],
  integrations: [...remoteCatalog.integrations, {
    id: "example-knowledge", revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", name: "Example knowledge", category_ids: ["knowledge"], availability: "available",
    documentation_url: "https://knowledge.example.test/docs",
    setup_url: "https://knowledge.example.test/setup",
    setup_notes: "Enable MCP access in your workspace before connecting.",
    connection: { type: "mcp", transport: "streamable_http", endpoint: "https://knowledge.example.test/mcp", authentication: { type: "none" } },
  }],
};

export function matchingMcpConnection(connections: Connection[], preset: Preset) {
  return preset.directoryId ? connections.find(connection => connection.preset.directoryId === preset.directoryId && connection.preset.id === preset.id) : undefined;
}

export type DirectoryPagination = {
  limit: number; total_items: number; start_index: number; end_index: number;
  next_cursor: string | null; previous_cursor: string | null;
};
export type RemotePage<T> = {
  schema_version: 1; resource: "categories" | "integrations"; directory_id: string; revision: string; items: T[];
  installation_version: string; pagination: DirectoryPagination;
};
export type RemoteCategoriesPage = RemotePage<RemoteCategory> & { resource: "categories" };
export type RemoteIntegrationsPage = RemotePage<RemoteIntegration> & { resource: "integrations"; query: { category: string | null; q: string; scope: "tenant" | "platform" } };

/** Remote search registry simulation; native implementations remain in the app. */
export function catalogWithProviders(catalog: RemoteDirectoryFixture, includeFuture = false): RemoteDirectoryFixture {
  const providers: RemoteProviderIntegration[] = setupProviders.map(provider => ({
    id: `provider-${provider.id}`, revision: 1, kind: "provider", minimum_vxpipe_version: "0.1.0", name: provider.name,
    category_ids: [provider.capabilities.includes("telephony") ? "telephony" : "ai"], availability: "available",
    documentation_url: "https://directory.example.test/providers",
    connection: { type: "builtin", provider_id: provider.id },
  }));
  if (includeFuture) providers.push({ id: "example-future", revision: 1, kind: "provider", minimum_vxpipe_version: "0.2.0", name: "Example future AI", category_ids: ["ai"], availability: "available", documentation_url: "https://future.example.test/docs", connection: { type: "builtin", provider_id: "future-ai" } });
  return { ...catalog, integrations: [...catalog.integrations, ...providers] };
}
