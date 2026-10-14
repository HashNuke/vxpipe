import { parseCallDirectoryItem, parseTenantPage, type TenantDirectoryPage } from "../adminApi";
import type { CallDirectoryItem } from "../callTypes";
import type { NavigationItem } from "./navigationPolicy";

export type NavigationFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
export type Capability = { read: boolean; write: boolean };
export type NavigationTenant = {
  key: string;
  name: string;
  dashboardPath: string;
  capabilities: Record<"calls" | "call_specs" | "services" | "api_keys", Capability>;
};
export type NavigationData = {
  actor: { id: string; kind: "member" | "admin" | "superadmin" };
  scope: "all" | "assigned";
  directoryAccess: boolean;
  directoryPath: "/tenants";
  landingPath: string;
  platform: NavigationItem[];
  tenant: NavigationTenant | null;
};
export type DashboardData = {
  tenant: NavigationTenant;
  recentCalls?: { status: "unavailable" } | { status: "ready"; calls: CallDirectoryItem[] };
};

export class NavigationError extends Error {
  constructor(readonly status: number) { super("Navigation request failed"); }
}

const defaultFetch: NavigationFetch = (input, init) => window.fetch(input, init);

export class NavigationApi {
  constructor(private readonly fetchImpl: NavigationFetch = defaultFetch, private readonly csrfToken = "") {}

  async createTenant(name: string): Promise<string> {
    const response = await this.fetchImpl("/admin/api/tenants", {
      method: "POST", credentials: "same-origin", cache: "no-store",
      headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": this.csrfToken },
      body: JSON.stringify({ name }),
    });
    if (!response.ok) throw new NavigationError(response.status);
    const tenant = record(record(await response.json()).tenant);
    if (typeof tenant.key !== "string" || !/^[A-Za-z0-9_-]{16}$/.test(tenant.key)) throw invalid();
    return tenant.key;
  }

  async navigation(tenantKey?: string, signal?: AbortSignal): Promise<NavigationData> {
    const query = tenantKey ? `?${new URLSearchParams({ tenant: tenantKey })}` : "";
    return parseNavigation(await this.get(`/admin/api/navigation${query}`, signal), tenantKey);
  }

  async tenants(query = "", page = 1, signal?: AbortSignal): Promise<TenantDirectoryPage> {
    const params = new URLSearchParams({ q: query, page: String(page), page_size: "25" });
    return parseTenantPage(await this.get(`/admin/api/tenants?${params}`, signal));
  }

  async dashboard(tenantKey: string, signal?: AbortSignal): Promise<DashboardData> {
    const data = record(await this.get(`/admin/api/tenants/${encodeURIComponent(tenantKey)}/dashboard`, signal));
    const tenant = parseTenant(data.tenant);
    if (tenant.key !== tenantKey) throw invalid();
    if (!tenant.capabilities.calls.read) {
      if (data.recent_calls !== undefined) throw invalid();
      return { tenant };
    }
    const recent = record(data.recent_calls);
    if (recent.status === "unavailable") return { tenant, recentCalls: { status: "unavailable" } };
    if (recent.status !== "ready" || !Array.isArray(recent.calls) || recent.calls.length > 5) throw invalid();
    return { tenant, recentCalls: { status: "ready", calls: recent.calls.map(parseCallDirectoryItem) } };
  }

  private async get(path: string, signal?: AbortSignal): Promise<unknown> {
    const response = await this.fetchImpl(path, {
      credentials: "same-origin", cache: "no-store", headers: { accept: "application/json" }, signal,
    });
    if (!response.ok) throw new NavigationError(response.status);
    return response.json();
  }
}

function parseNavigation(value: unknown, tenantKey?: string): NavigationData {
  const data = record(value);
  const actor = record(data.actor);
  if (typeof actor.id !== "string" || !actor.id ||
    (actor.kind !== "member" && actor.kind !== "admin" && actor.kind !== "superadmin") ||
    (data.tenant_scope !== "all" && data.tenant_scope !== "assigned") || typeof data.directory_access !== "boolean") throw invalid();
  const directoryPath = "/tenants";
  if (data.directory_path !== directoryPath || typeof data.landing_path !== "string" ||
    !(data.landing_path === directoryPath || (data.tenant_scope === "assigned" && /^\/t\/[A-Za-z0-9_-]{16}\/dashboard$/.test(data.landing_path)))) throw invalid();
  const tenant = data.tenant === null ? null : parseTenant(data.tenant);
  if ((tenantKey && tenant?.key !== tenantKey) || (!tenantKey && tenant !== null)) throw invalid();
  if (!Array.isArray(data.platform_destinations)) throw invalid();
  const platform = data.platform_destinations.map(parseDestination);
  return {
    actor: { id: actor.id, kind: actor.kind }, scope: data.tenant_scope, directoryAccess: data.directory_access,
    directoryPath, landingPath: data.landing_path, tenant, platform,
  };
}

function parseTenant(value: unknown): NavigationTenant {
  const tenant = record(value);
  if (typeof tenant.key !== "string" || !/^[A-Za-z0-9_-]{16}$/.test(tenant.key) ||
    typeof tenant.name !== "string" || !tenant.name || tenant.dashboard_path !== `/t/${tenant.key}/dashboard`) throw invalid();
  const capabilities = record(tenant.capabilities);
  return {
    key: tenant.key, name: tenant.name, dashboardPath: tenant.dashboard_path,
    capabilities: {
      calls: parseCapability(capabilities.calls), call_specs: parseCapability(capabilities.call_specs),
      services: parseCapability(capabilities.services), api_keys: parseCapability(capabilities.api_keys),
    },
  };
}

function parseCapability(value: unknown): Capability {
  const data = record(value);
  if (typeof data.read !== "boolean" || typeof data.write !== "boolean") throw invalid();
  return { read: data.read, write: data.write };
}

function parseDestination(value: unknown): NavigationItem {
  const data = record(value);
  const destinations: Record<string, NavigationItem> = {
    api_keys: { label: "API Keys", href: "/api-keys" },
    roles: { label: "Roles", href: "/roles" },
    users: { label: "Users", href: "/users" }, services: { label: "Services", href: "/platform/services" },
  };
  const destination = typeof data.id === "string" && Object.hasOwn(destinations, data.id) ? destinations[data.id] : undefined;
  if (!destination || data.label !== destination.label || data.path !== destination.href) throw invalid();
  return destination;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw invalid();
  return value as Record<string, unknown>;
}
function invalid() { return new Error("Invalid navigation response"); }
