import type { AccessLevel, Grant, Role } from "./types";

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
          grant.scope === "installation" ||
          (membership !== undefined &&
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
    tenant: true,
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
