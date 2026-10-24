import { expect, test } from "vitest";
import { roles, tenants, users } from "../authentication/fixtures";
import { landingPath, visibleTenants, navigationItems } from "./navigationPolicy";
import type { Role } from "../authentication/types";

test("only Superadmins see Installation in the Settings prototype", () => {
  expect(navigationItems(roles[0], users[0]).platform).toContainEqual({ label: "Installation", href: "/platform/installation" });
  for (const role of roles.slice(1)) {
    expect(navigationItems(role, users[1]).platform.some(item => item.href === "/platform/installation")).toBe(false);
  }
});

test("landing uses permission scope before tenant count, then zero/one/many visible tenants", () => {
  expect(landingPath(roles[0], users[0], tenants.slice(0, 1))).toBe("/tenants");
  expect(landingPath(roles[2], users[3], tenants)).toBe(`/t/${tenants[2].key}/dashboard`);
  expect(landingPath(roles[3], users[4], tenants)).toBe("/tenants");
  expect(landingPath(roles[3], users[7], tenants)).toBe("/tenants");
});
test("tenant directory excludes unassigned tenants and assignments without effective grants", () => {
  expect(visibleTenants(roles[3], users[4], tenants)).toEqual(tenants.slice(0, 2));
  expect(visibleTenants({ ...roles[3], grants: [] }, users[4], tenants)).toEqual([]);
});
test("mixed scopes expose all tenants but only permitted tenant destinations", () => {
  const role: Role = { ...roles[3], grants: [
    { permission: "calls.read", scope: "all_tenants" },
    { permission: "tenant_services.read", scope: "assigned_tenants" },
  ] };
  expect(landingPath(role, users[4], tenants)).toBe("/tenants");
  expect(navigationItems(role, users[4], tenants[2]).tenant.map(item => item.label)).toEqual(["Calls"]);
  expect(navigationItems(role, users[4], tenants[0]).tenant.map(item => item.label)).toEqual(["Calls", "Services"]);
  expect(navigationItems(role, users[4], tenants[2]).platform.map(item => item.label)).toEqual([]);
});
test("platform user reads do not imply role management or tenant access", () => {
  const role: Role = { ...roles[3], grants: [{ permission: "users.read", scope: "installation" }] };
  expect(navigationItems(role, users[4]).platform.map(item => item.label)).toEqual(["Users"]);
  expect(visibleTenants(role, users[4], tenants)).toEqual([]);
});

test("access-key permissions expose only API Keys in Settings for a tenant key manager", () => {
  const role: Role = { ...roles[3], grants: [
    { permission: "access_keys.read", scope: "assigned_tenants" },
    { permission: "access_keys.write", scope: "assigned_tenants" },
  ] };
  expect(navigationItems(role, users[4], tenants[0]).platform).toEqual([{ label: "API Keys", href: "/api-keys" }]);
  expect(navigationItems(role, users[4], tenants[0]).tenant).toEqual([]);
  expect(navigationItems(role, { ...users[4], memberships: [] }).platform).toEqual([]);
});
