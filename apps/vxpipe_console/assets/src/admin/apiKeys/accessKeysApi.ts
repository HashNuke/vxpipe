export type KeyKind = "calls" | "full" | "platform";
export type KeyTenant = { key: string; name: string };
export type AccessKey = { id: string; name: string; kind: KeyKind | "legacy_admin"; lastFour: string | null; tenant: KeyTenant | null; createdAt: string; canRevoke: boolean };
export type KeyPage = { keys: AccessKey[]; kinds: KeyKind[]; page: number; hasNext: boolean };
export type TenantPage = { tenants: KeyTenant[]; hasNext: boolean };
export interface AccessKeysClient {
  list(query: string, page: number, signal?: AbortSignal): Promise<KeyPage>;
  tenants(kind: KeyKind, query: string, page: number, signal?: AbortSignal): Promise<TenantPage>;
  create(name: string, kind: KeyKind, tenant: string | null): Promise<{ key: AccessKey; secret: string }>;
  revoke(id: string): Promise<void>;
}
export const keyLabels = { calls: "Create & Join Calls", full: "Full Tenant Access", platform: "Full Platform Access", legacy_admin: "Tenant administration (legacy)" };
type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
const object = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid API-key response");
  return value as Record<string, unknown>;
};
function tenant(value: unknown): KeyTenant {
  const row = object(value);
  if (typeof row.key !== "string" || typeof row.name !== "string") throw new Error("Invalid tenant");
  return { key: row.key, name: row.name };
}
function key(value: unknown): AccessKey {
  const row = object(value);
  if (typeof row.id !== "string" || typeof row.name !== "string" || typeof row.created_at !== "string" ||
    typeof row.can_revoke !== "boolean" || !["calls", "full", "platform", "legacy_admin"].includes(String(row.kind)) ||
    !(row.last_four === null || typeof row.last_four === "string")) throw new Error("Invalid API key");
  return { id: row.id, name: row.name, kind: row.kind as AccessKey["kind"], createdAt: row.created_at,
    canRevoke: row.can_revoke, lastFour: row.last_four, tenant: row.tenant === null ? null : tenant(row.tenant) };
}
export class AccessKeysApi implements AccessKeysClient {
  constructor(private readonly csrf: string, private readonly fetcher: Fetch = (input, init) => window.fetch(input, init), private readonly onFailure?: (status: number) => void) {}
  private async request(path: string, init?: RequestInit): Promise<unknown> {
    const response = await this.fetcher("/api/api-keys" + path, { credentials: "same-origin", cache: "no-store", ...init,
      headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": this.csrf } });
    if (!response.ok) { this.onFailure?.(response.status); throw new Error("API-key request failed"); }
    return response.status === 204 ? undefined : response.json();
  }
  async list(query: string, page: number, signal?: AbortSignal): Promise<KeyPage> {
    const data = object(await this.request("?" + new URLSearchParams({ q: query, page: String(page) }), { signal }));
    const pagination = object(data.pagination);
    if (!Array.isArray(data.keys) || !Array.isArray(data.creatable_kinds) || !data.creatable_kinds.every(k => ["calls", "full", "platform"].includes(String(k))) ||
      typeof pagination.page !== "number" || typeof pagination.has_next !== "boolean") throw new Error("Invalid API-key list");
    return { keys: data.keys.map(key), kinds: data.creatable_kinds as KeyKind[], page: pagination.page, hasNext: pagination.has_next };
  }
  async tenants(kind: KeyKind, query: string, page: number, signal?: AbortSignal): Promise<TenantPage> {
    const data = object(await this.request("/tenants?" + new URLSearchParams({ kind, q: query, page: String(page) }), { signal }));
    const pagination = object(data.pagination);
    if (!Array.isArray(data.tenants) || typeof pagination.has_next !== "boolean") throw new Error("Invalid tenant list");
    return { tenants: data.tenants.map(tenant), hasNext: pagination.has_next };
  }
  async create(name: string, kind: KeyKind, tenantKey: string | null) {
    const data = object(await this.request("", { method: "POST", body: JSON.stringify({ name, kind, tenant_key: tenantKey }) }));
    if (typeof data.secret !== "string") throw new Error("Invalid issued key");
    return { key: key(data.key), secret: data.secret };
  }
  async revoke(id: string) { await this.request("/" + encodeURIComponent(id), { method: "DELETE" }); }
}
