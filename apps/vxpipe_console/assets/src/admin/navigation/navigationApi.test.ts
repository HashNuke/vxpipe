import { expect, test, vi } from "vitest";
import { NavigationApi } from "./navigationApi";

const key = "AAAAAAAAAAAAAAAA";
const capability = { read: true, write: false };
const tenant = {
  key, name: "Acme", dashboard_path: `/t/${key}/dashboard`,
  capabilities: { calls: capability, call_specs: capability, services: capability, api_keys: capability },
};
const navigation = {
  actor: { id: "user", kind: "member" }, tenant_scope: "assigned", directory_access: true,
  landing_path: tenant.dashboard_path, directory_path: "/my-tenants", tenant,
  platform_destinations: [{ id: "users", label: "Users", path: "/users" }],
};
const response = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status });

test("loads the authoritative navigation with abort support and safe destinations", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(response(navigation));
  const signal = new AbortController().signal;
  const data = await new NavigationApi(fetchImpl).navigation(key, signal);
  expect(data).toMatchObject({ scope: "assigned", landingPath: tenant.dashboard_path, directoryAccess: true, platform: [{ label: "Users", href: "/users" }] });
  expect(data.tenant?.capabilities.api_keys.write).toBe(false);
  expect(fetchImpl).toHaveBeenCalledWith(`/admin/api/navigation?tenant=${key}`, expect.objectContaining({ signal, credentials: "same-origin", cache: "no-store" }));
});

test("does not accept foreign or malformed server destinations/capabilities", async () => {
  for (const value of [
    { ...navigation, landing_path: "//example.test" },
    { ...navigation, directory_path: "/users" },
    { ...navigation, platform_destinations: [{ id: "users", label: "Users", path: "https://example.test" }] },
    { ...navigation, tenant: { ...tenant, capabilities: {} } },
    { ...navigation, tenant: { ...tenant, key: "BBBBBBBBBBBBBBBB" } },
  ]) {
    const api = new NavigationApi(vi.fn().mockResolvedValue(response(value)));
    await expect(api.navigation(key)).rejects.toThrow("Invalid navigation response");
  }
});

test("search uses the same bounded paginated directory and URL-encodes literal search", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(response({
    tenants: [{ key, name: "Acme", created_at: "2026-10-13T00:00:00Z", dashboard_path: tenant.dashboard_path }],
    pagination: { page: 2, page_size: 25, total: 26, total_pages: 2, has_next: false },
  }));
  const result = await new NavigationApi(fetchImpl).tenants("100% & _", 2);
  expect(result.pagination.total).toBe(26);
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants?q=100%25+%26+_&page=2&page_size=25", expect.anything());
});

test("dashboard distinguishes unavailable calls from empty and omitted sections", async () => {
  for (const recent_calls of [{ status: "ready", calls: [] }, { status: "unavailable" }]) {
    const api = new NavigationApi(vi.fn().mockResolvedValue(response({ tenant, recent_calls })));
    expect((await api.dashboard(key)).recentCalls?.status).toBe(recent_calls.status);
  }
  const restricted = { ...tenant, capabilities: { ...tenant.capabilities, calls: { read: false, write: false } } };
  const api = new NavigationApi(vi.fn().mockResolvedValue(response({ tenant: restricted })));
  expect((await api.dashboard(key)).recentCalls).toBeUndefined();
});

test("dashboard validates tenant identity, bounded call rows and section access", async () => {
  const call = { id: "call-1", call_spec_id: "spec-1", call_spec_name: "Delivery", call_spec_revision: 1, state: "ongoing", created_at: "2026-10-13T00:00:00Z" };
  const valid = { tenant, recent_calls: { status: "ready", calls: [call] } };
  const api = new NavigationApi(vi.fn().mockResolvedValue(response(valid)));
  expect((await api.dashboard(key)).recentCalls).toMatchObject({ status: "ready", calls: [{ id: "call-1", callSpecName: "Delivery" }] });
  for (const value of [
    { ...valid, tenant: { ...tenant, key: "BBBBBBBBBBBBBBBB" } },
    { ...valid, recent_calls: { status: "ready", calls: Array(6).fill(call) } },
    { ...valid, recent_calls: { status: "ready", calls: [{}] } },
    { tenant },
  ]) {
    await expect(new NavigationApi(vi.fn().mockResolvedValue(response(value))).dashboard(key)).rejects.toThrow();
  }
});

test("HTTP failures keep status without reflecting arbitrary server details", async () => {
  for (const status of [401, 403, 404, 422, 503]) {
    const api = new NavigationApi(vi.fn().mockResolvedValue(response({ secret: "private" }, status)));
    await expect(api.navigation()).rejects.toMatchObject({ status, message: "Navigation request failed" });
  }
});
