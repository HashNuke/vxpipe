import { expect, test } from "vitest";

import { adminStoryPath, adminStoryRoute } from "./adminStoryRoute";

test("uses explicit tenant workspace destinations", () => {
  expect(
    adminStoryPath({ page: "call-specs", tenantKey: "tn demo" }),
  ).toBe("/admin/tenants/tn%20demo/call-specs");
  expect(adminStoryPath({ page: "calls", tenantKey: "tn demo" })).toBe(
    "/admin/tenants/tn%20demo/calls",
  );
  expect(adminStoryPath({ page: "services", tenantKey: "tn demo" })).toBe(
    "/admin/tenants/tn%20demo/services",
  );
  expect(adminStoryRoute("#/admin/tenants/tn%20demo/services")).toEqual({
    page: "services",
    tenantKey: "tn demo",
  });
});

test("round trips an optional call spec filter on tenant calls", () => {
  const path = adminStoryPath({
    page: "calls",
    tenantKey: "tn_demo_01",
    callSpecId: "delivery/rescheduling",
  });

  expect(path).toBe(
    "/admin/tenants/tn_demo_01/calls?call_spec_id=delivery%2Frescheduling",
  );
  expect(adminStoryRoute(`#${path}`)).toEqual({
    page: "calls",
    tenantKey: "tn_demo_01",
    callSpecId: "delivery/rescheduling",
  });
});

test("treats the tenant root as the call specs workspace entry", () => {
  expect(adminStoryRoute("#/admin/tenants/tn_demo_01")).toEqual({
    page: "call-specs",
    tenantKey: "tn_demo_01",
  });
  expect(adminStoryRoute("#/admin/tenants/tn_demo_01/call-specs")).toEqual({
    page: "call-specs",
    tenantKey: "tn_demo_01",
  });
});
