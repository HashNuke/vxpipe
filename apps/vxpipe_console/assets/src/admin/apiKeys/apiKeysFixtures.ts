import type { Role, User, Tenant } from "../authentication/types";
import { effectiveAccess } from "../authentication/access";
import type { AccessKey, AccessKeysClient, KeyKind } from "./accessKeysApi";

export function apiKeysFixture(role: Role, user: User, tenants: Tenant[], scenario = "existing", initial?: AccessKey[]): AccessKeysClient {
  const access = (tenant: Tenant, resource: string) => effectiveAccess(role, resource, user.memberships.find(m => m.tenantId === tenant.id)?.access);
  const canPlatformRead = !!role.kind || role.grants.some(g => g.permission === "platform_api_keys.read");
  const eligible = (kind: KeyKind) => tenants.filter(t => access(t, "access_keys") === "write" && access(t, "calls") === "write" &&
    (kind !== "full" || ["call_specs", "tenant_services", "tenant_api_keys"].every(resource => access(t, resource) === "write")));
  const kinds: KeyKind[] = [
    ...(eligible("calls").length ? ["calls" as const] : []),
    ...(eligible("full").length ? ["full" as const] : []),
    ...(role.kind === "superadmin" ? ["platform" as const] : []),
  ];
  let keys: AccessKey[] = initial ?? [
    { id: "demo-calls", name: "Website calls", kind: "calls", lastFour: "9x2a", tenant: tenants[0], createdAt: "2026-10-01T10:00:00Z", canRevoke: true },
    { id: "demo-full", name: "Operations", kind: "full", lastFour: "7f3b", tenant: tenants[1] ?? tenants[0], createdAt: "2026-10-10T10:00:00Z", canRevoke: true },
    { id: "demo-platform", name: "Platform automation", kind: "platform", lastFour: "2k8z", tenant: null, createdAt: "2026-10-14T10:00:00Z", canRevoke: true },
  ];
  return {
    async list(query, page) {
      if (scenario === "loading") return new Promise(() => {});
      if (scenario === "unavailable") throw new Error("Storybook unavailable");
      const visible = keys.filter(k => k.tenant ? tenants.some(t => t.key === k.tenant!.key && access(t, "access_keys") !== "none") : canPlatformRead)
        .filter(k => (k.name + " " + (k.tenant?.name ?? "")).toLowerCase().includes(query.toLowerCase()));
      return { keys: visible.slice((page - 1) * 25, page * 25).map(k => ({ ...k, canRevoke: k.tenant ? tenants.some(t => t.key === k.tenant!.key && access(t, "access_keys") === "write") : role.kind === "superadmin" })), kinds, page, hasNext: page * 25 < visible.length };
    },
    async tenants(kind, query, page) {
      const matches = eligible(kind).filter(t => (t.name + " " + t.key).toLowerCase().includes(query.toLowerCase()));
      return { tenants: matches.slice((page - 1) * 25, page * 25), hasNext: page * 25 < matches.length };
    },
    async create(name, kind, tenantKey) {
      if (scenario === "creating") return new Promise(() => {});
      if (scenario === "error") throw new Error("Storybook creation failed");
      if (!kinds.includes(kind)) throw new Error("Forbidden");
      const tenant = kind === "platform" ? null : eligible(kind).find(t => t.key === tenantKey);
      if (tenant === undefined) throw new Error("Select a tenant");
      const key: AccessKey = { id: "demo-" + (keys.length + 1), name, kind, tenant, lastFour: "-key", createdAt: new Date().toISOString(), canRevoke: true };
      keys = [...keys, key];
      return { key, secret: "storybook-nonfunctional-example-key" };
    },
    async revoke(id) { keys = keys.filter(k => k.id !== id); },
  };
}
