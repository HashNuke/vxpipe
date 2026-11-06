import { expect, test } from "vitest";
import { projectionAllowsPath } from "./navigationContext";
import type { NavigationData } from "./navigationApi";

test("category routes retain exact tenant and platform integration permissions", () => {
  const read = { read: true, write: false };
  const denied = { read: false, write: false };
  const data: NavigationData = { actor: { id: "member", kind: "member" }, scope: "assigned", directoryAccess: true,
    directoryPath: "/tenants", landingPath: "/tenants", platform: [],
    tenant: { key: "tenant-a", name: "A", dashboardPath: "/t/tenant-a/dashboard",
      capabilities: { calls: denied, call_specs: denied, services: read, api_keys: denied } } };
  expect(projectionAllowsPath(data, "/t/tenant-a/services/calendar")).toBe(true);
  expect(projectionAllowsPath(data, "/t/tenant-b/services/calendar")).toBe(false);
  expect(projectionAllowsPath(data, "/platform/services/ai")).toBe(false);
  expect(projectionAllowsPath({ ...data, platform: [{ label: "Services", href: "/platform/services" }] }, "/platform/services/ai")).toBe(true);
});
