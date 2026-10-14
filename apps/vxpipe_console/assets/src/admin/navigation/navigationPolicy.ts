import { canCreateTenants, effectiveAccess } from "../authentication/access";
import type { Role, Tenant, User } from "../authentication/types";

// Storybook presentation model only. Production consumes the server navigation projection.
const tenantResources = ["calls", "call_specs", "tenant_services"];
export type NavigationItem = { label: string; href: string };
export function allTenants(role: Role): boolean {
  return canCreateTenants(role) || role.grants.some(grant => grant.scope === "all_tenants" && tenantResources.some(resource => grant.permission === `${resource}.read`));
}
export function tenantAccess(role: Role, user: User, tenant: Tenant, resource: string) {
  return effectiveAccess(role, resource, user.memberships.find(item => item.tenantId === tenant.id)?.access);
}
export function visibleTenants(role: Role, user: User, tenants: Tenant[]): Tenant[] {
  return allTenants(role) ? tenants : tenants.filter(tenant => tenantResources.some(resource => tenantAccess(role, user, tenant, resource) !== "none"));
}
export function landingPath(role: Role, user: User, tenants: Tenant[]): string {
  if (allTenants(role)) return "/tenants";
  const visible = visibleTenants(role, user, tenants);
  return visible.length === 1 ? `/t/${encodeURIComponent(visible[0].key)}/dashboard` : "/my-tenants";
}
export function navigationItems(role: Role, user: User, tenant?: Tenant): { tenant: NavigationItem[]; platform: NavigationItem[] } {
  const allowed = (permission: string) => !!role.kind || role.grants.some(grant => grant.permission === permission && grant.scope === "installation");
  return {
    tenant: tenant ? [
      { label: "Calls", resource: "calls", path: "calls" },
      { label: "Call Specs", resource: "call_specs", path: "call-specs" },
      { label: "Services", resource: "tenant_services", path: "services" },
    ].filter(item => tenantAccess(role, user, tenant, item.resource) !== "none")
      .map(item => ({ label: item.label, href: `/t/${encodeURIComponent(tenant.key)}/${item.path}` })) : [],
    platform: [
      ...(allTenants(role) ? [{ label: "Tenants", href: "/tenants" }] : []),
      ...(role.kind ? [{ label: "Roles", href: "/roles" }] : []),
      ...(allowed("users.read") ? [{ label: "Users", href: "/users" }] : []),
      ...(allowed("platform_services.read") ? [{ label: "Services", href: "/platform/services" }] : []),
    ],
  };
}
