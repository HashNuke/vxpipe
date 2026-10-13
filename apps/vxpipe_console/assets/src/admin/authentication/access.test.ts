import { describe, expect, it } from "vitest";
import {
  canCreateCallSpecs,
  canCreateTenants,
  canManageUser,
  canReadPlatformServices,
  canWritePlatformServices,
  canWriteTenantCredentials,
  effectiveAccess,
  hasTenantServiceRead,
  membershipAccess,
  validatePassword,
  workspaceDestinationsFor,
} from "./access";
import { roles, users } from "./fixtures";

describe("account authority shown in the prototype", () => {
  it("allows Admins to manage members, but not privileged accounts or promotions", () => {
    const [superadmin, admin, , member] = roles;
    expect(canManageUser(admin, member)).toBe(true);
    expect(canManageUser(admin, admin)).toBe(false);
    expect(canManageUser(admin, superadmin)).toBe(false);
    expect(canManageUser(admin, member, admin)).toBe(false);
    expect(canManageUser(admin, admin, member)).toBe(false);
    expect(canManageUser(superadmin, admin)).toBe(true);
  });
  it("keeps reserved writes out of custom roles, even with a forged grant", () => {
    const [superadmin, admin, , member] = roles;
    expect(
      canManageUser(
        {
          ...member,
          grants: [
            { permission: "users.superadmins.write", scope: "installation" },
          ],
        },
        superadmin,
      ),
    ).toBe(false);
    expect(canManageUser(member, admin)).toBe(false);
  });
  it("caps assigned permissions without removing independent all-tenant grants", () => {
    const manager = roles[2];
    expect(effectiveAccess(manager, "calls")).toBe("none");
    expect(effectiveAccess(manager, "calls", "read")).toBe("read");
    expect(effectiveAccess(manager, "calls", "read_write")).toBe("write");
    const mixed = {
      ...manager,
      grants: [
        { permission: "calls.read", scope: "all_tenants" as const },
        { permission: "call_specs.read", scope: "assigned_tenants" as const },
      ],
    };
    expect(effectiveAccess(mixed, "calls")).toBe("read");
    expect(effectiveAccess(mixed, "call_specs", "read_write")).toBe("read");
  });
  it("validates the chosen password and confirmation without trimming it", () => {
    expect(
      validatePassword("an example passphrase", "different passphrase"),
    ).toMatch(/match/);
    expect(validatePassword("short", "short")).toMatch(/15/);
    expect(
      validatePassword(" an example passphrase ", "an example passphrase"),
    ).toMatch(/match/);
    expect(
      validatePassword("an example passphrase", "an example passphrase"),
    ).toBeUndefined();
  });
});

describe("operational capabilities derived from the server principal", () => {
  it("gates onboarding on tenant creation authority", () => {
    expect(canCreateTenants(roles[0])).toBe(true);
    expect(canCreateTenants(roles[1])).toBe(true);
    expect(canCreateTenants(roles[3])).toBe(false);
    expect(
      canCreateTenants({
        ...roles[3],
        grants: [{ permission: "tenants.write", scope: "installation" }],
      }),
    ).toBe(true);
  });
  it("gates platform services on the installation read key", () => {
    expect(canReadPlatformServices(roles[0])).toBe(true);
    expect(canReadPlatformServices(roles[3])).toBe(false);
    expect(
      canReadPlatformServices({
        ...roles[3],
        grants: [{ permission: "platform_services.read", scope: "installation" }],
      }),
    ).toBe(true);
  });
  it("separates platform service reading from writing", () => {
    const reader = { ...roles[3], grants: [{ permission: "platform_services.read", scope: "installation" as const }] };
    expect(canReadPlatformServices(reader)).toBe(true);
    expect(canWritePlatformServices(reader)).toBe(false);
    expect(canWritePlatformServices(roles[0])).toBe(true);
  });
  it("reads membership access by tenant key", () => {
    expect(membershipAccess(users[2], users[2].memberships[1].tenantId)).toBe(
      "read_write",
    );
    expect(membershipAccess(users[2], "no-such-tenant")).toBeUndefined();
  });
  it("derives workspace destinations from effective tenant reads", () => {
    expect(workspaceDestinationsFor(roles[0], undefined)).toEqual([
      "call-specs",
      "calls",
      "services",
    ]);
    expect(workspaceDestinationsFor(roles[3], "read")).toEqual([
      "call-specs",
      "calls",
    ]);
    expect(workspaceDestinationsFor(roles[3], undefined)).toEqual([]);
  });
  it("derives creation controls from effective tenant writes", () => {
    expect(canCreateCallSpecs(roles[2], "read_write")).toBe(true);
    expect(canCreateCallSpecs(roles[3], "read_write")).toBe(false);
    expect(canCreateCallSpecs(roles[2], "read")).toBe(false);
    expect(canCreateCallSpecs(roles[2], undefined)).toBe(false);
    expect(canWriteTenantCredentials(roles[2])).toBe(false);
    expect(
      canWriteTenantCredentials({
        ...roles[2],
        grants: [
          ...roles[2].grants,
          { permission: "tenant_api_keys.write", scope: "all_tenants" },
        ],
      }),
    ).toBe(true);
  });
  it("caps tenant service and API-key authority to the selected assignment", () => {
    const assignedManager = {
      ...roles[2],
      grants: [
        ...roles[2].grants,
        { permission: "tenant_services.read", scope: "assigned_tenants" as const },
        { permission: "tenant_services.write", scope: "assigned_tenants" as const },
        { permission: "tenant_api_keys.read", scope: "assigned_tenants" as const },
        { permission: "tenant_api_keys.write", scope: "assigned_tenants" as const },
      ],
    };
    expect(hasTenantServiceRead(assignedManager, "read_write")).toBe(true);
    expect(hasTenantServiceRead(assignedManager)).toBe(false);
    expect(canWriteTenantCredentials(assignedManager, "read_write")).toBe(true);
    expect(canWriteTenantCredentials(assignedManager, "read")).toBe(false);
    expect(workspaceDestinationsFor(assignedManager, "read_write")).toContain("services");
  });
});
