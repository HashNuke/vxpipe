import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./App";

vi.mock("@vxpipe/react", () => ({ CallConsole: () => <div>Call inspector</div> }));
vi.mock("./CallSpecEditorRoute", () => ({ CallSpecEditorRoute: () => <main>Call spec editor</main> }));
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

const key = "AAAAAAAAAAAAAAAA";
const other = "BBBBBBBBBBBBBBBB";
const capability = { read: true, write: false };
const tenant = (key: string) => ({ key, name: key === other ? "Beta" : "Acme", dashboard_path: `/t/${key}/dashboard`, capabilities: { calls: capability, call_specs: capability, services: capability, api_keys: capability } });
const user = { id: "user", email: "operator@example.test", enabled: true, roleId: "role", memberships: [{ tenantId: key, access: "read" }, { tenantId: other, access: "read" }] };
const role = { id: "role", name: "Reader", description: "", grants: ["calls.read", "call_specs.read", "tenant_services.read", "tenant_api_keys.read"].map(permission => ({ permission, scope: "assigned_tenants" })) };
const response = (data: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(data), { status }));
function fetcher({ directoryAccess = true, callsError = false } = {}) {
  return vi.fn((input: RequestInfo | URL) => {
    const url = new URL(String(input), "http://localhost");
    const selected = url.searchParams.get("tenant");
    if (url.pathname === "/auth/api/status") return response({ status: "complete" });
    if (url.pathname === "/admin/api/session") return response({ user, role });
    if (url.pathname === "/admin/api/navigation") return response({ actor: { id: "user", kind: "member" }, tenant_scope: "assigned", directory_access: directoryAccess, landing_path: "/my-tenants", directory_path: "/my-tenants", platform_destinations: [], tenant: selected ? tenant(selected) : null });
    if (url.pathname === "/admin/api/tenants") {
      const keys = url.searchParams.get("q")?.toLowerCase().includes("beta") ? [other] : [key, other];
      return response({ tenants: keys.map(key => ({ ...tenant(key), created_at: "2026-10-13T00:00:00Z" })), pagination: { page: 1, page_size: 25, total: keys.length, total_pages: 1, has_next: false } });
    }
    const routeKey = url.pathname.split("/")[4] ?? key;
    if (url.pathname.endsWith("/dashboard")) return response({ tenant: tenant(routeKey), recent_calls: callsError ? { status: "unavailable" } : { status: "ready", calls: [] } });
    if (url.pathname.endsWith("/call-specs")) return response({ tenant: tenant(routeKey), call_specs: [], pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 } });
    return response({}, 503);
  });
}

test("canonical dashboard uses the shared rail, server capabilities and real links", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  render(<App csrfToken="csrf" fetchImpl={fetcher()} />);
  expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeVisible();
  const rail = await screen.findByRole("complementary", { name: "Console navigation" });
  expect(within(rail).getByRole("combobox", { name: "Switch tenant" })).toHaveTextContent("Acme");
  expect(within(rail).getByRole("link", { name: "Calls" })).toHaveAttribute("href", `/t/${key}/calls`);
  expect(within(rail).getByRole("link", { name: "My account" })).toHaveAttribute("href", "/account");
  expect(screen.queryByRole("navigation", { name: "Platform" })).not.toBeInTheDocument();
  expect(screen.getByText("No calls yet")).toBeVisible();
  expect(screen.queryByText(key)).not.toBeInTheDocument();
});

test("remote tenant search switches from a resource page to the chosen dashboard", async () => {
  window.history.replaceState({}, "", `/t/${key}/call-specs`);
  const fetchImpl = fetcher();
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await waitFor(() => expect(screen.getByRole("combobox", { name: "Switch tenant" })).toHaveTextContent("Acme"));
  fireEvent.click(screen.getByRole("combobox", { name: "Switch tenant" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Search tenants" }), { target: { value: "Beta" } });
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith(expect.stringContaining("q=Beta"), expect.objectContaining({ signal: expect.any(AbortSignal) })));
  fireEvent.click(await screen.findByRole("option", { name: /Beta/ }));
  await waitFor(() => expect(window.location.pathname).toBe(`/t/${other}/dashboard`));
  expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeVisible();
});

test("no-access directory renders its empty state without fetching tenants", async () => {
  window.history.replaceState({}, "", "/my-tenants");
  const fetchImpl = fetcher({ directoryAccess: false });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("heading", { name: "My tenants" })).toBeVisible();
  expect(screen.getByText("No tenant access")).toBeVisible();
  expect(fetchImpl.mock.calls.some(([input]) => new URL(String(input), "http://localhost").pathname === "/admin/api/tenants")).toBe(false);
});

test("partial dashboard failure stays distinct from empty without a retry button", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  render(<App csrfToken="csrf" fetchImpl={fetcher({ callsError: true })} />);
  expect(await screen.findByText("Recent calls unavailable")).toBeVisible();
  expect(screen.queryByText("No calls yet")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Try again" })).not.toBeInTheDocument();
});

test("editor and history routes do not mount the private navigation", async () => {
  for (const path of [`/admin/tenants/${key}/call-specs/new`, `/admin/tenants/${key}/calls/call-id`]) {
    window.history.replaceState({}, "", path);
    const fetchImpl = fetcher();
    const view = render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
    await waitFor(() => expect(view.container.querySelector("main")).not.toBeNull());
    expect(screen.queryByRole("complementary", { name: "Console navigation" })).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.some(([input]) => String(input).startsWith("/admin/api/navigation"))).toBe(false);
    view.unmount();
  }
});

test("API-key-only permission exposes Services without Calls or Call Specs", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  const base = fetcher();
  const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const value = await base(input);
    if (String(input).includes("/navigation") || String(input).endsWith("/dashboard")) {
      const body = await value.json();
      body.tenant.capabilities.calls = { read: false, write: false };
      body.tenant.capabilities.call_specs = { read: false, write: false };
      body.tenant.capabilities.services = { read: false, write: false };
      delete body.recent_calls;
      return response(body);
    }
    void init;
    return value;
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  const rail = await screen.findByRole("complementary");
  await waitFor(() => expect(within(rail).getByRole("link", { name: "Services" })).toBeVisible());
  expect(within(rail).queryByRole("link", { name: "Calls" })).not.toBeInTheDocument();
  expect(within(rail).queryByRole("link", { name: "Call Specs" })).not.toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "Recent calls" })).not.toBeInTheDocument();
});

test("a revoked selected tenant clears old workspace data and resolves a fresh landing", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  const base = fetcher();
  let revoked = false;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (revoked && String(input).startsWith("/admin/api/navigation?")) return response({}, 404);
    if (revoked && String(input) === "/admin/api/navigation") return response({ actor: { id: "user", kind: "member" }, tenant_scope: "assigned", directory_access: false, landing_path: "/my-tenants", directory_path: "/my-tenants", platform_destinations: [], tenant: null });
    return base(input);
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByText("No calls yet");
  revoked = true;
  fireEvent(window, new Event("focus"));
  expect(await screen.findByText("No tenant access")).toBeVisible();
  expect(window.location.pathname).toBe("/my-tenants");
  expect(screen.queryByText("Acme")).not.toBeInTheDocument();
});

test("a late tenant-search response cannot replace a newer query", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  const base = fetcher();
  let resolveOld: (response: Response) => void = () => {};
  let oldSignal: AbortSignal | undefined;
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input).includes("q=Acme")) {
      oldSignal = init?.signal ?? undefined;
      return new Promise<Response>(resolve => { resolveOld = resolve; });
    }
    return base(input);
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByText("No calls yet");
  fireEvent.click(screen.getByRole("combobox", { name: "Switch tenant" }));
  const search = screen.getByRole("combobox", { name: "Search tenants" });
  fireEvent.change(search, { target: { value: "Acme" } });
  await waitFor(() => expect(oldSignal).toBeDefined());
  fireEvent.change(search, { target: { value: "Beta" } });
  await screen.findByRole("option", { name: /Beta/ });
  expect(oldSignal?.aborted).toBe(true);
  resolveOld(await response({ tenants: [{ key, name: "Old result", created_at: "2026-10-13T00:00:00Z" }], pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 } }));
  await waitFor(() => expect(screen.getByRole("option", { name: /Beta/ })).toBeVisible());
  expect(screen.queryByRole("option", { name: /Old result/ })).not.toBeInTheDocument();
});

test("revoking a resource read hides the open resource even when other tenant access remains", async () => {
  window.history.replaceState({}, "", `/t/${key}/call-specs`);
  let revoked = false;
  const base = fetcher();
  const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
    const result = await base(input);
    if (revoked && String(input).startsWith("/admin/api/navigation?")) {
      const body = await result.json();
      body.tenant.capabilities.call_specs = { read: false, write: false };
      return response(body);
    }
    return result;
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("No call specs yet")).toBeVisible();
  revoked = true;
  fireEvent(window, new Event("focus"));
  expect(await screen.findByRole("heading", { name: "Access unavailable" })).toBeVisible();
  expect(screen.queryByText("No call specs yet")).not.toBeInTheDocument();
});

test("refreshing authority also refreshes an already open tenant directory", async () => {
  window.history.replaceState({}, "", "/my-tenants");
  let revoked = false;
  const base = fetcher();
  const fetchImpl = vi.fn((input: RequestInfo | URL) => revoked && String(input).startsWith("/admin/api/tenants?")
    ? response({ tenants: [{ key: other, name: "Beta", created_at: "2026-10-13T00:00:00Z" }], pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 } }) : base(input));
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByRole("link", { name: "Open Acme" });
  revoked = true;
  fireEvent(window, new Event("focus"));
  await waitFor(() => expect(screen.queryByRole("link", { name: "Open Acme" })).not.toBeInTheDocument());
  expect(await screen.findByRole("link", { name: "Open Beta" })).toBeVisible();
});

test("session expiry clears private navigation and account identity", async () => {
  window.history.replaceState({}, "", `/t/${key}/dashboard`);
  let expired = false;
  const base = fetcher();
  const onSessionExpired = vi.fn();
  const fetchImpl = vi.fn((input: RequestInfo | URL) => expired && String(input).startsWith("/admin/api/navigation") ? response({}, 401) : base(input));
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} onSessionExpired={onSessionExpired} />);
  await screen.findByText("No calls yet");
  expect(screen.getByText("operator@example.test")).toBeVisible();
  expired = true;
  fireEvent(window, new Event("focus"));
  await waitFor(() => expect(onSessionExpired).toHaveBeenCalledOnce());
  expect(screen.queryByText("operator@example.test")).not.toBeInTheDocument();
  expect(screen.queryByRole("navigation", { name: "Tenant" })).not.toBeInTheDocument();
});

test("tenant creators can create a tenant and land on its dashboard", async () => {
  window.history.replaceState({}, "", "/my-tenants");
  const base = fetcher();
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input) === "/admin/api/session") return response({ user, role: { ...role, grants: [...role.grants, { permission: "tenants.write", scope: "installation" }] } });
    if (String(input) === "/admin/api/tenants" && init?.method === "POST") return response({ tenant: { key: other, name: "Beta", created_at: "2026-10-13T00:00:00Z", dashboard_path: `/t/${other}/dashboard` } }, 201);
    return base(input);
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  fireEvent.click(await screen.findByRole("link", { name: "New tenant" }));
  fireEvent.change(await screen.findByRole("textbox", { name: "Give your tenant a name" }), { target: { value: "Beta" } });
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  await waitFor(() => expect(window.location.pathname).toBe(`/t/${other}/dashboard`));
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants", expect.objectContaining({ method: "POST", body: JSON.stringify({ name: "Beta" }), headers: expect.objectContaining({ "x-csrf-token": "csrf" }) }));
});

test("readers cannot open the tenant creation form", async () => {
  window.history.replaceState({}, "", "/tenants/new");
  render(<App csrfToken="csrf" fetchImpl={fetcher()} />);
  expect(await screen.findByRole("heading", { name: "Access unavailable" })).toBeVisible();
  expect(screen.queryByRole("textbox", { name: "Give your tenant a name" })).not.toBeInTheDocument();
});

test("tenant directory searches remotely and shows creation dates", async () => {
  window.history.replaceState({}, "", "/my-tenants");
  const fetchImpl = fetcher();
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByRole("link", { name: "Open Acme" });
  expect(screen.getAllByText(/^Created /)).toHaveLength(2);
  expect(screen.queryByRole("link", { name: "New tenant" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("textbox", { name: "Find a tenant" }), { target: { value: "Beta" } });
  await waitFor(() => expect(screen.queryByRole("link", { name: "Open Acme" })).not.toBeInTheDocument());
  expect(await screen.findByRole("link", { name: "Open Beta" })).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(expect.stringContaining("q=Beta"), expect.anything());
});
