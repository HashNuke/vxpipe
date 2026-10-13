import type { AccessLevel, Grant, Role, User } from "./types";
import type { TenantDestination } from "../TenantWorkspaceNavigation";

// Presentation policy for the isolated prototype. Backend authorization must recheck it.
export function canManageUser(
  actor: Role,
  target: Role,
  next = target,
): boolean {
  if (!actor.kind) return false;
  return actor.kind === "superadmin" || (!target.kind && !next.kind);
}
export function canReadUsers(role: Role): boolean {
  return (
    !!role.kind ||
    role.grants.some((grant) => grant.permission === "users.read")
  );
}
export function effectiveAccess(
  role: Role,
  resource: string,
  membership?: AccessLevel,
): "none" | "read" | "write" {
  if (role.kind) return "write";
  const allows = (action: string) =>
    role.grants.some(
      (grant) =>
        grant.permission === `${resource}.${action}` &&
        (grant.scope === "all_tenants" ||
          (grant.scope === "assigned_tenants" && membership !== undefined &&
            (action === "read" || membership === "read_write"))),
    );
  return allows("write") ? "write" : allows("read") ? "read" : "none";
}
export function hasAssignedGrants(role: Role): boolean {
  return (
    !role.kind &&
    role.grants.some((grant) => grant.scope === "assigned_tenants")
  );
}
export function validatePassword(
  password: string,
  confirmation: string,
): string | undefined {
  if (password !== confirmation)
    return "Passwords do not match. Enter the same password in both fields.";
  if (Array.from(password).length < 15 || Array.from(password).length > 128)
    return "Use a password between 15 and 128 characters.";
  return undefined;
}
export const permissionGroups = [
  {
    resource: "calls",
    label: "Calls",
    detail: "View history; start and control calls.",
    tenant: true,
  },
  {
    resource: "call_specs",
    label: "Call specs",
    detail: "View source; create, edit and publish specs.",
    tenant: true,
  },
  {
    resource: "tenant_services",
    label: "Tenant services",
    detail: "Inspect and configure tenant-owned services.",
    tenant: true,
  },
  {
    resource: "tenant_api_keys",
    label: "Tenant API keys",
    detail: "View metadata; issue and revoke keys.",
    tenant: true,
  },
  {
    resource: "tenants",
    label: "Tenants",
    detail: "View tenant details; manage tenant settings.",
    tenant: false,
  },
  {
    resource: "platform_services",
    label: "Platform services",
    detail: "Inspect metadata; configure and test shared services.",
    tenant: false,
  },
  {
    resource: "users",
    label: "User directory",
    detail: "View users of every role. Account writes are reserved.",
    tenant: false,
    readOnly: true,
  },
  {
    resource: "diagnostics",
    label: "Diagnostics",
    detail: "View platform diagnostics.",
    tenant: false,
    readOnly: true,
  },
];
export function operationalGrants(
  scope: "all_tenants" | "assigned_tenants",
): Grant[] {
  return permissionGroups
    .filter((group) => group.tenant)
    .flatMap((group) => [
      { permission: `${group.resource}.read`, scope },
      { permission: `${group.resource}.write`, scope },
    ]);
}

/**
 * Operational visibility derived from the server principal. Installation
 * resources authorize on the exact permission key (scope is validated at
 * role-write time), so link visibility checks the key, never client claims.
 */
export function canCreateTenants(role: Role): boolean {
  return !!role.kind || role.grants.some((grant) => grant.permission === "tenants.write");
}

export function canReadPlatformServices(role: Role): boolean {
  return (
    !!role.kind ||
    role.grants.some(
      (grant) =>
        grant.permission === "platform_services.read" ||
        grant.permission === "platform_services.write",
    )
  );
}

export function canWritePlatformServices(role: Role): boolean {
  return !!role.kind || role.grants.some(
    (grant) => grant.permission === "platform_services.write" && grant.scope === "installation",
  );
}

export function membershipAccess(user: User, tenantKey: string): AccessLevel | undefined {
  return user.memberships.find((item) => item.tenantId === tenantKey)?.access;
}

export function hasTenantServiceRead(role: Role, access?: AccessLevel): boolean {
  return effectiveAccess(role, "tenant_services", access) !== "none";
}

export function canWriteTenantCredentials(role: Role, access?: AccessLevel): boolean {
  return effectiveAccess(role, "tenant_api_keys", access) === "write";
}

export function workspaceDestinationsFor(
  role: Role,
  access?: AccessLevel,
): TenantDestination[] {
  const destinations: TenantDestination[] = [];
  if (effectiveAccess(role, "call_specs", access) !== "none")
    destinations.push("call-specs");
  if (effectiveAccess(role, "calls", access) !== "none") destinations.push("calls");
  if (hasTenantServiceRead(role, access)) destinations.push("services");
  return destinations;
}

export function canCreateCallSpecs(role: Role, access?: AccessLevel): boolean {
  return effectiveAccess(role, "call_specs", access) === "write";
}
