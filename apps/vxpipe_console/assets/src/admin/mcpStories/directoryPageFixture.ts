import type { DirectoryRequest } from "./directoryRequest";
import type { RemoteDirectoryFixture, RemoteIntegration, RemoteIntegrationsPage } from "./remoteDirectory";

/** Simulates a server-owned query; the UI consumes only this returned page. */
export function directoryPageFixture(catalog: RemoteDirectoryFixture, request: DirectoryRequest): RemoteIntegrationsPage | null {
  const { category, query, cursor, limit, scope, headers } = request;
  const version = new Headers(headers).get("X-VxPipe-Version");
  if (!version) throw new Error("X-VxPipe-Version is required");
  const compare = (left: string, right: string) => {
    const a = left.split(".").map(Number), b = right.split(".").map(Number);
    return a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
  };
  const q = query.trim().toLowerCase();
  const items = catalog.integrations.filter(item => (!category || item.category_ids.includes(category)) && (scope === "tenant" || item.kind === "provider") && (!item.minimum_vxpipe_version || compare(version, item.minimum_vxpipe_version) >= 0) && (!item.maximum_vxpipe_version_exclusive || compare(version, item.maximum_vxpipe_version_exclusive) < 0) && `${item.name} ${item.summary ?? ""}`.toLowerCase().includes(q))
    .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
  const key = [catalog.revision, category, q, limit, version, scope];
  const token = (offset: number) => btoa(encodeURIComponent(JSON.stringify([...key, offset])));
  let offset = 0;
  if (cursor) {
    try {
      const decoded = JSON.parse(decodeURIComponent(atob(cursor)));
      if (!Array.isArray(decoded) || decoded.length !== 7 || JSON.stringify(decoded.slice(0, 6)) !== JSON.stringify(key)) return null;
      offset = decoded[6];
      if (!Number.isInteger(offset) || offset < 0 || offset % limit !== 0 || offset >= items.length) return null;
    } catch { return null; }
  }
  return {
    schema_version: 1, resource: "integrations", directory_id: catalog.directory_id, revision: catalog.revision,
    installation_version: version, query: { category, q, scope }, items: items.slice(offset, offset + limit),
    pagination: {
      limit, total_items: items.length, start_index: items.length ? offset + 1 : 0, end_index: Math.min(offset + limit, items.length),
      previous_cursor: offset ? token(Math.max(0, offset - limit)) : null,
      next_cursor: offset + limit < items.length ? token(offset + limit) : null,
    },
  };
}
export function paginatedFixture(catalog: RemoteDirectoryFixture): RemoteDirectoryFixture {
  const samples: RemoteIntegration[] = ["Acme appointments", "Aster calendar", "Beacon scheduling"].map((name, index) => ({
    id: `example-calendar-${index}`, name, revision: 1, kind: "mcp", minimum_vxpipe_version: "0.1.0", category_ids: ["calendar"], availability: "available",
    documentation_url: "https://calendar.example.test/docs",
    connection: { type: "mcp", transport: "streamable_http", endpoint: `https://calendar.example.test/${index}/mcp`, authentication: { type: "none" } },
  }));
  return { ...catalog, categories: catalog.categories.map(item => item.id === "calendar" ? { ...item, integration_count: item.integration_count + samples.length } : item), integrations: [...catalog.integrations, ...samples] };
}
