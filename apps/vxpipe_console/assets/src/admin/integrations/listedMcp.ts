export type McpRecipe = { type: "none" | "bearer" | "basic" } |
  { type: "api_key"; header_name: string } |
  { type: "oauth2"; registration: "discover" | "cimd" | "dcr" | "preregistered"; scopes?: string[] };
export type McpDirectoryEntry = {
  directory_id: string; integration_id: string; revision: number; name: string; endpoint: string;
  authentication: McpRecipe; setup_notes?: string; setup_url?: string; documentation_url?: string;
};
export type McpListingReference = {
  directory_id: string; integration_id: string; entry_revision: number; page: Record<string, string | number>;
};
export type McpListing = { reference: McpListingReference; entry: McpDirectoryEntry };

const object = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown, max: number): value is string => typeof value === "string" && value.length > 0 && value.length <= max;
const identifier = (value: unknown): value is string => text(value, 64) && /^[a-z][a-z0-9-]*$/.test(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && Number(value) > 0;
const invalid = () => new Error("The MCP directory configuration is unavailable. Reload integrations.");

function https(value: unknown, endpoint = false): value is string {
  if (!text(value, 2048) || /\s/.test(value)) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !!url.hostname && !url.username && !url.password &&
      (!endpoint || (!url.search && !url.hash));
  } catch { return false; }
}

function recipe(value: unknown): McpRecipe {
  if (!object(value)) throw invalid();
  if (value.type === "none" || value.type === "bearer" || value.type === "basic") return { type: value.type };
  if (value.type === "api_key" && text(value.header_name, 128) && /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(value.header_name))
    return { type: "api_key", header_name: value.header_name };
  if (value.type === "oauth2" && ["discover", "cimd", "dcr", "preregistered"].includes(String(value.registration))) {
    if (value.scopes !== undefined && (!Array.isArray(value.scopes) || value.scopes.length > 64 || !value.scopes.every(scope => text(scope, 256) && /^[\x21\x23-\x5b\x5d-\x7e]+$/.test(scope)))) throw invalid();
    return { type: "oauth2", registration: value.registration as Extract<McpRecipe, { type: "oauth2" }>["registration"], ...(value.scopes ? { scopes: value.scopes as string[] } : {}) };
  }
  throw invalid();
}

export function parseDirectoryEntry(value: unknown): McpDirectoryEntry {
  if (!object(value) || !identifier(value.directory_id) || !identifier(value.integration_id) || !positive(value.revision) ||
    !text(value.name, 100) || !https(value.endpoint, true) || JSON.stringify(value).length > 65536) throw invalid();
  const result: McpDirectoryEntry = { directory_id: value.directory_id, integration_id: value.integration_id,
    revision: value.revision, name: value.name, endpoint: value.endpoint, authentication: recipe(value.authentication) };
  if (value.setup_notes !== undefined) {
    if (typeof value.setup_notes !== "string" || value.setup_notes.length > 1000) throw invalid();
    result.setup_notes = value.setup_notes;
  }
  for (const field of ["setup_url", "documentation_url"] as const) {
    if (value[field] !== undefined) {
      if (!https(value[field])) throw invalid();
      result[field] = value[field];
    }
  }
  return result;
}

export function parseListing(row: Record<string, unknown>): McpListing | undefined {
  if (row.listing === undefined) return undefined;
  const reference = row.listing;
  if (!object(reference) || !identifier(reference.directory_id) || !identifier(reference.integration_id) ||
    !positive(reference.entry_revision) || reference.integration_id !== row.id || reference.entry_revision !== row.revision ||
    !object(reference.page) || JSON.stringify(reference).length > 8192 || !object(row.connection) ||
    Object.keys(reference).some(key => !["directory_id", "integration_id", "entry_revision", "page"].includes(key))) throw invalid();
  const page: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(reference.page)) {
    const valid = key === "scope" ? value === "tenant" : key === "limit" ? positive(value) && value <= 100 :
      key === "category" ? identifier(value) : key === "q" ? typeof value === "string" && value.length <= 200 :
        ["cursor", "revision"].includes(key) && text(value, 2048);
    if (!valid) throw invalid();
    page[key] = value as string | number;
  }
  return { reference: { directory_id: reference.directory_id, integration_id: reference.integration_id, entry_revision: reference.entry_revision, page },
    entry: parseDirectoryEntry({ directory_id: reference.directory_id, integration_id: row.id, revision: row.revision, name: row.name,
      endpoint: row.connection.endpoint, authentication: row.connection.authentication,
      ...(row.setup_notes !== undefined ? { setup_notes: row.setup_notes } : {}),
      ...(row.setup_url !== undefined ? { setup_url: row.setup_url } : {}),
      ...(row.documentation_url !== undefined ? { documentation_url: row.documentation_url } : {}) }) };
}

export function listedMethod(entry?: McpDirectoryEntry): "" | "none" | "bearer" | "basic" | "headers" {
  const type = entry?.authentication.type;
  return type === "api_key" ? "headers" : type === "none" || type === "bearer" || type === "basic" ? type : "";
}
