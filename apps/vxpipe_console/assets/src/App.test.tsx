import { modelCatalogFixture } from "./admin/modelCatalogFixtures";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, expect, test, vi } from "vitest";

import { App } from "./test/ResourceApp";

vi.mock("@vxpipe/react", () => ({
  CallConsole: ({
    header,
    headerContext,
  }: {
    header?: ReactNode;
    headerContext?: ReactNode;
  }) => (
    <div data-testid="call-console">
      {header}
      {headerContext}
    </div>
  ),
}));

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/tenants");
});

const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

const operationalUser = {
  id: "owner",
  email: "owner@example.test",
  roleId: "superadmin",
  enabled: true,
  memberships: [],
};
const operationalRole = {
  id: "superadmin",
  name: "Superadmin",
  description: "",
  kind: "superadmin",
  grants: [],
};
const operationalSession = { user: operationalUser, role: operationalRole };

test("first-run setup submits credentials and opens the Console", async () => {
  window.history.replaceState({}, "", "/auth/setup");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    response(String(input).includes("/auth/api/status") ? { status: "pending_first_run" } : { ok: true }),
  );
  const authenticated = vi.fn();
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} onAuthenticated={authenticated} />);

  expect(await screen.findByRole("heading", { name: "Set up your installation" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "owner@example.test" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "an example passphrase" } });
  fireEvent.click(screen.getByRole("button", { name: /Create Superadmin account/ }));

  await waitFor(() => expect(authenticated).toHaveBeenCalledOnce());
  expect(fetchImpl).toHaveBeenCalledWith("/auth/api/setup", expect.objectContaining({ method: "POST" }));
});

test("the production users route renders server-filtered rows and role filters", async () => {
  window.history.replaceState({}, "", "/users");
  const owner = { id: "owner", email: "owner@example.test", roleId: "superadmin", enabled: true, memberships: [] };
  const role = { id: "superadmin", name: "Superadmin", description: "", kind: "superadmin", grants: [] };
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const path = String(input);
    if (path === "/admin/api/session") return response({ user: owner, role });
    if (path === "/admin/api/roles") return response({ roles: [role] });
    if (path.startsWith("/admin/api/users"))
      return response({ users: [owner], pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 } });
    return response({});
  });

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("heading", { name: "Users", level: 1 })).toBeVisible();
  expect(screen.getByRole("table", { name: "Users" }).tagName).toBe("TABLE");
  fireEvent.change(screen.getByRole("combobox", { name: "Filter by role" }), { target: { value: "superadmin" } });
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith(
    expect.stringContaining("/admin/api/users?role=superadmin"), expect.any(Object)
  ));
});

const tenantPage = (page: number, name = "Example tenant") => ({
  tenants: Array.from({ length: page === 1 ? 25 : 5 }, (_, index) => ({
    key: `tenant${page}${index}`.padEnd(16, "0"),
    name: index === 0 ? name : `Tenant ${page}-${index}`,
    created_at: "2026-09-17T01:00:00Z",
  })),
  pagination: { page, page_size: 25, total: 30, total_pages: 2 },
});

const callSpecPage = (
  tenantKey: string,
  tenantName: string,
  callSpecName: string,
) => ({
  tenant: { key: tenantKey, name: tenantName },
  call_specs: [
    {
      id: "delivery-rescheduling",
      name: callSpecName,
      latest_revision: 4,
      published_revision: 3,
      call_count: 5,
      updated_at: "2026-09-17T03:00:00Z",
    },
  ],
  pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
});

const callPage = (
  tenantKey: string,
  selectedCallSpecId: string | null,
  page = 1,
) => ({
  tenant: { key: tenantKey, name: "Example tenant" },
  call_specs: [
    { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    { id: "appointment-reminders", name: "Appointment reminders" },
  ],
  call_specs_truncated: false,
  selected_call_spec_id: selectedCallSpecId,
  calls:
    selectedCallSpecId === "appointment-reminders"
      ? []
      : [
          {
            id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
            call_spec_id: "delivery-rescheduling",
            call_spec_name: "Delivery rescheduling",
            call_spec_revision: 3,
            state: "ongoing",
            created_at: "2026-09-17T02:20:00Z",
          },
        ],
  pagination:
    page === 2
      ? { page: 2, page_size: 25, total: 26, total_pages: 2 }
      : {
          page: 1,
          page_size: 25,
          total: selectedCallSpecId === "appointment-reminders" ? 0 : 1,
          total_pages: selectedCallSpecId === "appointment-reminders" ? 0 : 1,
        },
});

const serviceDirectory = (tenantKey: string, credentials = true) => ({
  tenant: { key: tenantKey, name: "Example tenant" },
  truncated: false,
  credentials: credentials
    ? [
        {
          id: "credential-google",
          provider: "google",
          name: "primary",
          auth_kind: "api_key",
          status: "active",
          credential_preview: [
            { label: "API key", format: "last_four", last_four: "8c4a" },
          ],
          last_validated_at: "2026-09-17T01:55:00Z",
          created_at: "2026-09-17T02:00:00Z",
          updated_at: "2026-09-17T02:00:00Z",
        },
      ]
    : [],
  telephony_services: [],
});

test("retires tenant setup services in favor of the service inventory", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input) === "/admin/api/session"
      ? response(operationalSession)
      : response(serviceDirectory("AAAAAAAAAAAAAAAA", false)),
  );

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("No services yet")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/services",
    expect.any(Object),
  );
});

const callDetailsResponse = (state: "running" | "ended" = "running") => ({
  tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
  call_spec: { id: "delivery-rescheduling", name: "Delivery rescheduling" },
  call_spec_revision: 3,
  inspection: {
    schema_version: 1,
    call: {
      id: "call-public-id",
      revision: state === "running" ? 3 : 4,
      state,
      created_at: "2026-09-17T02:20:00Z",
      started_at: "2026-09-17T02:20:03Z",
      ended_at: state === "ended" ? "2026-09-17T02:22:17Z" : null,
      terminal_reason: state === "ended" ? "completed" : null,
      duration_ms: state === "ended" ? 134_000 : null,
    },
    incarnation: { room_id: "room-1", incarnation_id: "incarnation-1" },
    participants: [],
    timeline: [],
    variables: { state: "unavailable", reason: "not-captured" },
    metrics: [],
    metrics_availability: { state: "unavailable", reason: "not-loaded" },
    completeness: {
      state: state === "ended" ? "complete" : "unconfirmed",
      missing_sequence_count: 0,
      dropped_live_records: 0,
    },
  },
});

test("loads the scoped tenant page with sidebar account actions", async () => {
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input) === "/admin/api/session"
      ? response(operationalSession)
      : response(tenantPage(1)),
  );
  render(
    <App csrfToken="csrf-test-token" fetchImpl={fetchImpl} />,
  );

  expect(await screen.findByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Logout" })).toBeVisible();
  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/session", expect.any(Object));
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants?q=&page=1&page_size=25", expect.objectContaining({
    headers: { accept: "application/json" },
    signal: expect.any(AbortSignal),
  }));

});

test("an empty installation opens onboarding only when explicitly selected", async () => {
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (url.startsWith("/admin/api/tenants?")) {
      return response({
        tenants: [],
        pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
      });
    }
    if (url === "/admin/api/onboarding/demo-tenant") {
      return response({
        tenant: {
          key: "DEMOabcdefgh1234",
          name: "Demo",
          created_at: "2026-09-18T05:00:00Z",
        },
      });
    }
    return response({
      tenant: { key: "DEMOabcdefgh1234", name: "Demo" },
      bindings: [],
      model_catalog: modelCatalogFixture, provider_capabilities: {},
    });
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("No tenants yet")).toBeVisible();
  expect(window.location.pathname).toBe("/tenants");
  expect(screen.getByRole("link", { name: "New tenant" })).toHaveAttribute("href", "/tenants/new");
  cleanup();
  window.history.replaceState({}, "", "/getting-started");
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(
    await screen.findByRole("heading", { name: "Demo tenant is ready" }),
  ).toBeVisible();
  expect(
    screen.getByRole("heading", { name: "Connect your services" }),
  ).toBeVisible();
  expect(window.location.pathname).toBe("/getting-started");
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/onboarding/demo-tenant", {
    method: "POST",
    headers: {
      accept: "application/json",
      "x-csrf-token": "csrf",
    },
    signal: expect.any(AbortSignal),
  });
});

test("shows unavailable and expired-session outcomes truthfully", async () => {
  const expired = vi.fn();
  const { rerender } = render(
    <App
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Your workspace could not be loaded",
  );

  rerender(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({}, 401)
      }
      onSessionExpired={expired}
    />,
  );
  window.dispatchEvent(new PopStateEvent("popstate"));

  await waitFor(() => expect(expired).toHaveBeenCalledOnce());
});

test("restores page navigation from browser history and ignores a stale response", async () => {
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });

  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return first;
    if (operationalCalls === 2) return response(tenantPage(2, "Second page tenant"));
    return response(tenantPage(1));
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  await waitFor(() => expect(operationalCalls).toBe(1));
  window.history.pushState({}, "", "/tenants?page=2");
  window.dispatchEvent(new PopStateEvent("popstate"));

  expect(await screen.findByText("Second page tenant")).toBeVisible();
  resolveFirst?.(await response(tenantPage(1, "Stale tenant")));

  await waitFor(() =>
    expect(screen.queryByText("Stale tenant")).not.toBeInTheDocument(),
  );

  fireEvent.click(screen.getByRole("button", { name: "Previous page" }));
  expect(window.location.pathname + window.location.search).toBe("/tenants");
});

test("ignores an expired-session response from an obsolete request", async () => {
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  const expired = vi.fn();
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return first;
    if (operationalCalls === 2) return response(tenantPage(2, "Current tenant"));
    return response(tenantPage(1));
  });

  render(
    <App
      csrfToken="csrf"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );

  await waitFor(() => expect(operationalCalls).toBe(1));
  window.history.pushState({}, "", "/tenants?page=2");
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current tenant")).toBeVisible();

  await act(async () => {
    resolveFirst?.(await response({}, 401));
    await first;
  });

  expect(expired).not.toHaveBeenCalled();
});

test("recovers an out-of-range page to the first tenant page", async () => {
  window.history.replaceState({}, "", "/tenants?page=999");
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return response({ error: { code: "invalid_page" } }, 422);
    return response(tenantPage(1));
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe("/tenants");
  expect(fetchImpl).toHaveBeenNthCalledWith(
    1,
    "/admin/api/session",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    2,
    "/admin/api/tenants?q=&page=999&page_size=25",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    3,
    "/admin/api/tenants?q=&page=1&page_size=25",
    expect.any(Object),
  );
});

test("opens a tenant's approved call specs page and canonicalizes the workspace URL", async () => {
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (url.startsWith("/admin/api/tenants?")) return response(tenantPage(1));
    if (url.endsWith("/dashboard")) return response(dashboard("tenant1000000000"));
    if (url.includes("/calls?")) {
      return response(callPage("tenant1000000000", "delivery-rescheduling"));
    }
    return response(
      callSpecPage("tenant1000000000", "Example tenant", "Delivery rescheduling"),
    );
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  fireEvent.click(
    await screen.findByRole("link", { name: "Open Example tenant" }),
  );
  await screen.findByText("No calls yet");
  fireEvent.click(within(screen.getByRole("complementary")).getByRole("link", { name: "Call Specs" }));

  expect(
    await screen.findByRole("heading", { name: "Call Specs" }),
  ).toBeVisible();
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/t/tenant1000000000/call-specs",
  );
  expect(screen.getByRole("link", { name: "Calls" })).toBeVisible();
  expect(within(screen.getByRole("navigation", { name: "Tenant" })).getByRole("link", { name: "Services" })).toBeVisible();
  expect(
    screen.getByRole("link", {
      name: "View 5 calls for Delivery rescheduling",
    }),
  ).toHaveAttribute(
    "href",
    "/t/tenant1000000000/calls?call_spec_id=delivery-rescheduling",
  );

  fireEvent.click(
    screen.getByRole("link", {
      name: "View 5 calls for Delivery rescheduling",
    }),
  );
  expect(await screen.findByRole("heading", { name: "Calls" })).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/t/tenant1000000000/calls?call_spec_id=delivery-rescheduling",
  );
});

test("loads filtered tenant calls and updates the URL when the filter changes", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/calls?call_spec_id=delivery-rescheduling&page=2",
  );

  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (url.includes("/calls/spec-options?")) return response({ options: [{ id: "appointment-reminders", name: "Appointment reminders" }], has_more: false });
    const selected = url.includes("appointment-reminders")
      ? "appointment-reminders"
      : "delivery-rescheduling";
    return response(
      callPage("AAAAAAAAAAAAAAAA", selected, url.includes("page=2") ? 2 : 1),
    );
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByText("018f27cb-6f87-7d1c-a61f-8873cb667342"),
  ).toBeVisible();
  expect(screen.getByRole("link", { name: "Call Specs" })).toBeVisible();
  expect(within(screen.getByRole("navigation", { name: "Tenant" })).getByRole("link", { name: "Services" })).toBeVisible();
  expect(
    screen.getByRole("link", { name: /open call 018f27cb/i }),
  ).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=2&call_spec_id=delivery-rescheduling",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/session", expect.any(Object));

  fireEvent.click(screen.getByRole("combobox", { name: "Call spec" }));
  fireEvent.click(
    await screen.findByRole("option", { name: "Appointment reminders" }),
  );

  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants/AAAAAAAAAAAAAAAA/calls/spec-options?q=&page=1", expect.objectContaining({ signal: expect.any(AbortSignal) }));
  expect(await screen.findByText("No matching calls")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/t/AAAAAAAAAAAAAAAA/calls?call_spec_id=appointment-reminders",
  );
});

test("loads an approved call details route into the reusable console", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
  );
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input) === "/admin/api/session"
      ? response(operationalSession)
      : response(callDetailsResponse()),
  );

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByRole("heading", { name: "Call details" }),
  ).toBeInTheDocument();
  expect(screen.getByText("call-public-id")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/session", expect.any(Object));
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
    expect.objectContaining({ signal: expect.any(AbortSignal) }),
  );
});

test("opens call details in a new tab without replacing the call directory", async () => {
  window.history.replaceState({}, "", "/t/AAAAAAAAAAAAAAAA/calls");
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    return url.endsWith("/calls?page=1")
      ? response(callPage("AAAAAAAAAAAAAAAA", null))
      : response({
          ...callDetailsResponse(),
          inspection: {
            ...callDetailsResponse().inspection,
            call: {
              ...callDetailsResponse().inspection.call,
              id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
            },
          },
        });
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  const call = await screen.findByRole("link", { name: /open call 018f27cb/i });
  expect(call).toHaveAttribute("target", "_blank");
  expect(call).toHaveAttribute("rel", "noopener noreferrer");
  expect(call).toHaveAttribute(
    "href",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/018f27cb-6f87-7d1c-a61f-8873cb667342",
  );
  fireEvent.click(call);
  expect(screen.queryByTestId("call-console")).not.toBeInTheDocument();
  expect(window.location.pathname).toBe(
    "/t/AAAAAAAAAAAAAAAA/calls",
  );
  expect(fetchImpl).toHaveBeenCalledTimes(2);
  expect(fetchImpl).toHaveBeenNthCalledWith(1, "/admin/api/session", expect.any(Object));
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=1",
    expect.any(Object),
  );
});

test("keeps missing, malformed, unavailable, and expired call details distinct", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
  );
  const expired = vi.fn();
  const view = render(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({}, 404)
      }
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "This call could not be found",
  );

  view.rerender(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({ tenant: "invalid" })
      }
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("Call data could not be read")).toBeVisible();

  view.rerender(
    <App
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Call inspection is unavailable",
  );

  view.rerender(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({}, 401)
      }
      onSessionExpired={expired}
    />,
  );
  await waitFor(() => expect(expired).toHaveBeenCalledOnce());
});

test("ignores an expired-session response from an obsolete call-details request", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
  );
  let resolveDetails: ((value: Response) => void) | undefined;
  const pendingDetails = new Promise<Response>((resolve) => {
    resolveDetails = resolve;
  });
  const expired = vi.fn();
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return pendingDetails;
    return response(tenantPage(1, "Current tenant"));
  });

  render(
    <App
      csrfToken="csrf"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );

  window.history.pushState({}, "", "/tenants");
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current tenant")).toBeVisible();

  await act(async () => {
    resolveDetails?.(await response({}, 401));
    await pendingDetails;
  });

  expect(expired).not.toHaveBeenCalled();
});

test("ignores an obsolete call response after the call spec filter changes", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/calls?call_spec_id=delivery-rescheduling",
  );
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return first;
    return response(callPage("AAAAAAAAAAAAAAAA", "appointment-reminders"));
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/calls?call_spec_id=appointment-reminders",
  );
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("No matching calls")).toBeVisible();

  await act(async () => {
    resolveFirst?.(
      await response(callPage("AAAAAAAAAAAAAAAA", "delivery-rescheduling")),
    );
    await first;
  });

  expect(
    screen.queryByText("018f27cb-6f87-7d1c-a61f-8873cb667342"),
  ).not.toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Call spec" })).toHaveTextContent(
    "Appointment reminders",
  );
});

test("recovers an out-of-range call page without losing its call spec filter", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/calls?page=999&call_spec_id=delivery-rescheduling",
  );
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1)
      return response({ error: { code: "invalid_page" } }, 422);
    return response(callPage("AAAAAAAAAAAAAAAA", "delivery-rescheduling"));
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByText("018f27cb-6f87-7d1c-a61f-8873cb667342"),
  ).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/t/AAAAAAAAAAAAAAAA/calls?call_spec_id=delivery-rescheduling",
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    1,
    "/admin/api/session",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    2,
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=999&call_spec_id=delivery-rescheduling",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    3,
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=1&call_spec_id=delivery-rescheduling",
    expect.any(Object),
  );
});

test("keeps missing and unavailable call directories distinct", async () => {
  window.history.replaceState({}, "", "/t/AAAAAAAAAAAAAAAA/calls");
  const { rerender } = render(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({}, 404)
      }
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "tenant or call spec could not be found",
  );

  rerender(
    <App
      csrfToken="csrf"
      fetchImpl={input => String(input) === "/admin/api/session" ? response(operationalSession) : Promise.reject(new Error("offline"))}
    />,
  );
  window.dispatchEvent(new PopStateEvent("popstate"));

  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Calls could not be loaded",
    ),
  );
});

test("redirects a tenant workspace root to the dashboard on direct load", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input) === "/admin/api/session"
      ? response(operationalSession)
      : response(
          dashboard("AAAAAAAAAAAAAAAA"),
        ),
  );

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("No calls yet")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/t/AAAAAAAAAAAAAAAA/dashboard",
  );
});

test("canonicalizes unknown admin routes to the tenant directory", async () => {
  window.history.replaceState({}, "", "/admin/not-a-real-page");

  render(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response(tenantPage(1))
      }
    />,
  );

  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(window.location.pathname).toBe("/tenants");
});

test("ignores an obsolete call spec response after switching tenants", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/call-specs",
  );
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  let operationalCalls = 0;
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response(operationalSession);
    operationalCalls += 1;
    if (operationalCalls === 1) return first;
    return response(
      callSpecPage("BBBBBBBBBBBBBBBB", "Tenant B", "Current call spec"),
    );
  });

  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState(
    {},
    "",
    "/t/BBBBBBBBBBBBBBBB/call-specs",
  );
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current call spec")).toBeVisible();

  await act(async () => {
    resolveFirst?.(
      await response(
        callSpecPage("AAAAAAAAAAAAAAAA", "Tenant A", "Stale call spec"),
      ),
    );
    await first;
  });

  expect(screen.queryByText("Stale call spec")).not.toBeInTheDocument();
});

test("keeps empty, missing, and unavailable call spec states distinct", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/call-specs",
  );
  const empty = {
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    call_specs: [],
    pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
  };
  const { rerender } = render(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response(empty)
      }
    />,
  );

  expect(await screen.findByText("No call specs yet")).toBeVisible();

  rerender(
    <App
      csrfToken="csrf"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({ error: { code: "tenant_not_found" } }, 404)
      }
    />,
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "tenant could not be found",
  );

  rerender(
    <App
      csrfToken="csrf"
      fetchImpl={input => String(input) === "/admin/api/session" ? response(operationalSession) : Promise.reject(new Error("offline"))}
    />,
  );
  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Call specs could not be loaded",
    ),
  );
});

test("loads the approved services page directly and exposes all tenant destinations", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input) === "/admin/api/session"
      ? response(operationalSession)
      : response(serviceDirectory("AAAAAAAAAAAAAAAA")),
  );

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByRole("heading", { name: "Services" }),
  ).toBeVisible();
  expect(await screen.findAllByText("Google AI Studio")).not.toHaveLength(0);
  expect(screen.getByRole("link", { name: "Call Specs" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Calls" })).toBeVisible();
  expect(within(screen.getByRole("navigation", { name: "Tenant" })).getByRole("link", { name: "Services" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/session", expect.any(Object));
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/services",
    expect.objectContaining({ signal: expect.any(AbortSignal) }),
  );
});

test("submits write-only credential values with CSRF and updates metadata after success", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi.fn(
    (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === "/admin/api/session") return response(operationalSession);
      if (init?.method === "POST") {
        expect(init).toMatchObject({
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            "x-csrf-token": "csrf-token",
          },
        });
        expect(JSON.parse(String(init?.body))).toEqual({
          provider: "google",
          values: { api_key: "private-value" },
        });
        return response(
          {
            credential: {
              id: "credential-google",
              provider: "google",
              name: "primary",
              auth_kind: "api_key",
              status: "active",
              credential_preview: [
                { label: "API key", format: "last_four", last_four: "alue" },
              ],
              last_validated_at: "2026-09-17T01:55:00Z",
              created_at: "2026-09-17T02:00:00Z",
              updated_at: "2026-09-17T02:00:00Z",
            },
          },
          201,
        );
      }
      return response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
    },
  );

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("No services yet")).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  expect(screen.getByRole("complementary", { hidden: true })).toHaveAttribute("inert");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(screen.getByRole("status", { name: "Notification" })).toHaveTextContent("Service saved.");
  expect(await screen.findAllByText("Google AI Studio")).not.toHaveLength(0);
  expect(screen.queryByDisplayValue("private-value")).not.toBeInTheDocument();
});

test("replaces credentials from the edit dialog and refreshes their safe preview", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (init?.method === "PATCH") {
      expect(String(input)).toBe(
        "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials/credential-google",
      );
      expect(init?.method).toBe("PATCH");
      expect(JSON.parse(String(init?.body))).toEqual({
        provider: "google",
        values: { api_key: "replacement-7f2b" },
      });
      return response({
        credential: {
          id: "credential-google",
          provider: "google",
          name: "google",
          auth_kind: "api_key",
          status: "active",
          credential_preview: [
            { label: "API key", format: "last_four", last_four: "7f2b" },
          ],
          last_validated_at: "2026-09-18T01:55:00Z",
          created_at: "2026-09-17T02:00:00Z",
          updated_at: "2026-09-18T02:00:00Z",
        },
      });
    }
    return response(serviceDirectory("AAAAAAAAAAAAAAAA"));
  });

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("****8c4a")).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Edit Google AI Studio credentials" }),
  );
  expect(screen.getByLabelText("Provider")).toBeDisabled();
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "replacement-7f2b" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByText("****7f2b")).toBeVisible();
  expect(screen.queryByText("****8c4a")).not.toBeInTheDocument();
});

test("ignores a stale credential submission after leaving the tenant services page", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  const expired = vi.fn();
  let resolveCreate: ((value: Response) => void) | undefined;
  const pendingCreate = new Promise<Response>((resolve) => {
    resolveCreate = resolve;
  });
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (init?.method === "POST") return pendingCreate;
    if (url.includes("/call-specs")) {
      return response(
        callSpecPage(
          "AAAAAAAAAAAAAAAA",
          "Example tenant",
          "Current call spec",
        ),
      );
    }
    return response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
  });

  render(
    <App
      csrfToken="csrf-token"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  window.history.pushState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/call-specs",
  );
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current call spec")).toBeVisible();

  await act(async () => {
    resolveCreate?.(
      await response({ error: { code: "credential_already_exists" } }, 409),
    );
    await pendingCreate;
  });

  expect(screen.queryByText(/already exists/i)).not.toBeInTheDocument();
  expect(expired).not.toHaveBeenCalled();
});

test("ignores a credential response after its dialog is closed and reopened", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  let resolveCreate: ((value: Response) => void) | undefined;
  const pendingCreate = new Promise<Response>((resolve) => {
    resolveCreate = resolve;
  });
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    return init?.method === "POST"
      ? pendingCreate
      : response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
  });

  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "first-secret" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  fireEvent.click(
    screen.getByRole("button", { name: "Close credential setup" }),
  );

  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "second-secret" },
  });

  await act(async () => {
    resolveCreate?.(
      await response(
        {
          credential: {
            id: "credential-first",
            provider: "google",
            name: "first",
            auth_kind: "api_key",
            status: "active",
            credential_preview: [],
            last_validated_at: "2026-09-17T01:55:00Z",
            created_at: "2026-09-17T02:00:00Z",
            updated_at: "2026-09-17T02:00:00Z",
          },
        },
        201,
      ),
    );
    await pendingCreate;
  });

  expect(screen.getByRole("dialog", { name: "Connect a service" })).toBeVisible();
  expect(screen.getByLabelText("API key")).toHaveValue("second-secret");
});

test("presents service load, duplicate, and expired-session outcomes truthfully", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );
  const expired = vi.fn();
  const unavailableView = render(
    <App
      csrfToken="csrf-token"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Your workspace could not be loaded",
  );
  unavailableView.unmount();

  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === "/admin/api/session") return response(operationalSession);
    if (init?.method === "POST") {
      return response({ error: { code: "credential_already_exists" } }, 409);
    }
    return response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
  });

  render(
    <App
      csrfToken="csrf-token"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(await screen.findByRole("alert", { name: "Notification" })).toHaveTextContent("already exists");

  cleanup();
  render(
    <App
      csrfToken="csrf-token"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response({}, 401)
      }
      onSessionExpired={expired}
    />,
  );
  await waitFor(() => expect(expired).toHaveBeenCalledOnce());
});

test("rejects a service directory for a different tenant", async () => {
  window.history.replaceState(
    {},
    "",
    "/t/AAAAAAAAAAAAAAAA/services",
  );

  render(
    <App
      csrfToken="csrf-token"
      fetchImpl={(input: RequestInfo | URL) =>
        String(input) === "/admin/api/session"
          ? response(operationalSession)
          : response(serviceDirectory("BBBBBBBBBBBBBBBB"))
      }
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Services could not be loaded",
  );
  expect(screen.queryByText("Credential stored")).not.toBeInTheDocument();
});

function dashboard(key: string) {
  const capability = { read: true, write: true };
  return { tenant: { key, name: "Example tenant", dashboard_path: `/t/${key}/dashboard`, capabilities: { calls: capability, call_specs: capability, services: capability, api_keys: capability } }, recent_calls: { status: "ready", calls: [] } };
}
