import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, expect, test, vi } from "vitest";

import { AdminApp } from "./AdminApp";

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
  window.history.replaceState({}, "", "/admin");
});

const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

const tenantPage = (page: number, name = "Example tenant") => ({
  tenants: Array.from({ length: page === 1 ? 25 : 5 }, (_, index) => ({
    key: `tenant-${page}-${index}`,
    name: index === 0 ? name : `Tenant ${page}-${index}`,
    created_at: "2026-09-17T01:00:00Z",
  })),
  pagination: { page, page_size: 25, total: 30, total_pages: 2 },
});

const definitionPage = (
  tenantKey: string,
  tenantName: string,
  definitionName: string,
) => ({
  tenant: { key: tenantKey, name: tenantName },
  definitions: [
    {
      id: "delivery-rescheduling",
      name: definitionName,
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
  selectedDefinitionId: string | null,
  page = 1,
) => ({
  tenant: { key: tenantKey, name: "Example tenant" },
  definitions: [
    { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    { id: "appointment-reminders", name: "Appointment reminders" },
  ],
  definitions_truncated: false,
  selected_definition_id: selectedDefinitionId,
  calls:
    selectedDefinitionId === "appointment-reminders"
      ? []
      : [
          {
            id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
            definition_id: "delivery-rescheduling",
            definition_name: "Delivery rescheduling",
            definition_revision: 3,
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
          total: selectedDefinitionId === "appointment-reminders" ? 0 : 1,
          total_pages: selectedDefinitionId === "appointment-reminders" ? 0 : 1,
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

const callDetailsResponse = (state: "running" | "ended" = "running") => ({
  tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
  definition: { id: "delivery-rescheduling", name: "Delivery rescheduling" },
  definition_revision: 3,
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

test("loads the approved tenant page with a CSRF-protected sign-out action", async () => {
  const fetchImpl = vi.fn(() => response(tenantPage(1)));
  const view = render(
    <AdminApp csrfToken="csrf-test-token" fetchImpl={fetchImpl} />,
  );

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Sign out" })).toBeVisible();
  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants?page=1", {
    headers: { accept: "application/json" },
    signal: expect.any(AbortSignal),
  });
  expect(
    view.container.querySelector('form[action="/auth/logout"]'),
  ).toHaveAttribute("method", "post");
  expect(view.container.querySelector('input[name="_csrf_token"]')).toHaveValue(
    "csrf-test-token",
  );
});

test("shows empty, unavailable, and expired-session outcomes truthfully", async () => {
  const expired = vi.fn();
  const { rerender } = render(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() =>
        response({
          tenants: [],
          pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
        })
      }
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByText("No tenants yet")).toBeVisible();

  rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );
  window.dispatchEvent(new PopStateEvent("popstate"));

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Tenant data could not be loaded",
  );

  rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({}, 401)}
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

  const fetchImpl = vi
    .fn(() => response(tenantPage(1)))
    .mockImplementationOnce(() => first)
    .mockImplementationOnce(() =>
      response(tenantPage(2, "Second page tenant")),
    );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState({}, "", "/admin?page=2");
  window.dispatchEvent(new PopStateEvent("popstate"));

  expect(await screen.findByText("Second page tenant")).toBeVisible();
  resolveFirst?.(await response(tenantPage(1, "Stale tenant")));

  await waitFor(() =>
    expect(screen.queryByText("Stale tenant")).not.toBeInTheDocument(),
  );

  fireEvent.click(screen.getByRole("button", { name: "Previous page" }));
  expect(window.location.pathname + window.location.search).toBe("/admin");
});

test("ignores an expired-session response from an obsolete request", async () => {
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  const expired = vi.fn();
  const fetchImpl = vi
    .fn(() => response(tenantPage(1)))
    .mockImplementationOnce(() => first)
    .mockImplementationOnce(() => response(tenantPage(2, "Current tenant")));

  render(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );

  window.history.pushState({}, "", "/admin?page=2");
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current tenant")).toBeVisible();

  await act(async () => {
    resolveFirst?.(await response({}, 401));
    await first;
  });

  expect(expired).not.toHaveBeenCalled();
});

test("recovers an out-of-range page to the first tenant page", async () => {
  window.history.replaceState({}, "", "/admin?page=999");
  const fetchImpl = vi
    .fn(() => response(tenantPage(1)))
    .mockImplementationOnce(() =>
      response({ error: { code: "invalid_page" } }, 422),
    );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe("/admin");
  expect(fetchImpl).toHaveBeenNthCalledWith(
    1,
    "/admin/api/tenants?page=999",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    2,
    "/admin/api/tenants?page=1",
    expect.any(Object),
  );
});

test("opens a tenant's approved definitions page and canonicalizes the workspace URL", async () => {
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.startsWith("/admin/api/tenants?")) return response(tenantPage(1));
    if (url.includes("/calls?")) {
      return response(callPage("tenant-1-0", "delivery-rescheduling"));
    }
    return response(
      definitionPage("tenant-1-0", "Example tenant", "Delivery rescheduling"),
    );
  });

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  fireEvent.click(
    await screen.findByRole("link", { name: "Open Example tenant" }),
  );

  expect(
    await screen.findByRole("heading", { name: "Call definitions" }),
  ).toBeVisible();
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/admin/tenants/tenant-1-0/definitions",
  );
  expect(screen.getByRole("link", { name: "Calls" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Services" })).toBeVisible();
  expect(
    screen.getByRole("link", {
      name: "View 5 calls for Delivery rescheduling",
    }),
  ).toHaveAttribute(
    "href",
    "/admin/tenants/tenant-1-0/calls?definition_id=delivery-rescheduling",
  );

  fireEvent.click(
    screen.getByRole("link", {
      name: "View 5 calls for Delivery rescheduling",
    }),
  );
  expect(await screen.findByRole("heading", { name: "Calls" })).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/admin/tenants/tenant-1-0/calls?definition_id=delivery-rescheduling",
  );
});

test("loads filtered tenant calls and updates the URL when the filter changes", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?definition_id=delivery-rescheduling&page=2",
  );

  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    const selected = url.includes("appointment-reminders")
      ? "appointment-reminders"
      : "delivery-rescheduling";
    return response(
      callPage("AAAAAAAAAAAAAAAA", selected, url.includes("page=2") ? 2 : 1),
    );
  });

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByText("018f27cb-6f87-7d1c-a61f-8873cb667342"),
  ).toBeVisible();
  expect(screen.getByRole("link", { name: "Call definitions" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Services" })).toBeVisible();
  expect(
    screen.getByRole("link", { name: /open call 018f27cb/i }),
  ).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=2&definition_id=delivery-rescheduling",
    expect.any(Object),
  );

  fireEvent.click(screen.getByRole("combobox", { name: "Call spec" }));
  fireEvent.click(
    screen.getByRole("option", { name: "Appointment reminders" }),
  );

  expect(await screen.findByText("No matching calls")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?definition_id=appointment-reminders",
  );
});

test("loads an approved call details route into the reusable console", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
  );
  const fetchImpl = vi.fn(() => response(callDetailsResponse()));

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByRole("heading", { name: "Call details" }),
  ).toBeInTheDocument();
  expect(screen.getByText("call-public-id")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
    expect.objectContaining({ signal: expect.any(AbortSignal) }),
  );
});

test("opens call details in a new tab without replacing the call directory", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/calls");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    String(input).endsWith("/calls?page=1")
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
        }),
  );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);
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
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls",
  );
  expect(fetchImpl).toHaveBeenCalledTimes(1);
});

test("keeps missing, malformed, unavailable, and expired call details distinct", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls/call-public-id",
  );
  const expired = vi.fn();
  const view = render(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({}, 404)}
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "This call could not be found",
  );

  view.rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({ tenant: "invalid" })}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("Call data could not be read")).toBeVisible();

  view.rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Call inspection is unavailable",
  );

  view.rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({}, 401)}
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
  const fetchImpl = vi
    .fn(() => response(tenantPage(1, "Current tenant")))
    .mockImplementationOnce(() => pendingDetails);

  render(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );

  window.history.pushState({}, "", "/admin");
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current tenant")).toBeVisible();

  await act(async () => {
    resolveDetails?.(await response({}, 401));
    await pendingDetails;
  });

  expect(expired).not.toHaveBeenCalled();
});

test("ignores an obsolete call response after the definition filter changes", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?definition_id=delivery-rescheduling",
  );
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  const fetchImpl = vi
    .fn(() => response(callPage("AAAAAAAAAAAAAAAA", "appointment-reminders")))
    .mockImplementationOnce(() => first);

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?definition_id=appointment-reminders",
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

test("recovers an out-of-range call page without losing its definition filter", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?page=999&definition_id=delivery-rescheduling",
  );
  const fetchImpl = vi
    .fn(() => response(callPage("AAAAAAAAAAAAAAAA", "delivery-rescheduling")))
    .mockImplementationOnce(() =>
      response({ error: { code: "invalid_page" } }, 422),
    );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByText("018f27cb-6f87-7d1c-a61f-8873cb667342"),
  ).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe(
    "/admin/tenants/AAAAAAAAAAAAAAAA/calls?definition_id=delivery-rescheduling",
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    1,
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=999&definition_id=delivery-rescheduling",
    expect.any(Object),
  );
  expect(fetchImpl).toHaveBeenNthCalledWith(
    2,
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/calls?page=1&definition_id=delivery-rescheduling",
    expect.any(Object),
  );
});

test("keeps missing and unavailable call directories distinct", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/calls");
  const { rerender } = render(
    <AdminApp csrfToken="csrf" fetchImpl={() => response({}, 404)} />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "tenant or call definition could not be found",
  );

  rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
    />,
  );
  window.dispatchEvent(new PopStateEvent("popstate"));

  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Calls could not be loaded",
    ),
  );
});

test("redirects a tenant workspace root to definitions on direct load", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA");
  const fetchImpl = vi.fn(() =>
    response(
      definitionPage("AAAAAAAAAAAAAAAA", "Example tenant", "Direct definition"),
    ),
  );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Direct definition")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/admin/tenants/AAAAAAAAAAAAAAAA/definitions",
  );
});

test("ignores an obsolete definition response after switching tenants", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/definitions",
  );
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  const fetchImpl = vi
    .fn(() =>
      response(
        definitionPage("BBBBBBBBBBBBBBBB", "Tenant B", "Current definition"),
      ),
    )
    .mockImplementationOnce(() => first);

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState(
    {},
    "",
    "/admin/tenants/BBBBBBBBBBBBBBBB/definitions",
  );
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current definition")).toBeVisible();

  await act(async () => {
    resolveFirst?.(
      await response(
        definitionPage("AAAAAAAAAAAAAAAA", "Tenant A", "Stale definition"),
      ),
    );
    await first;
  });

  expect(screen.queryByText("Stale definition")).not.toBeInTheDocument();
});

test("keeps empty, missing, and unavailable definition states distinct", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/definitions",
  );
  const empty = {
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    definitions: [],
    pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
  };
  const { rerender } = render(
    <AdminApp csrfToken="csrf" fetchImpl={() => response(empty)} />,
  );

  expect(await screen.findByText("No call definitions yet")).toBeVisible();

  rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({ error: { code: "tenant_not_found" } }, 404)}
    />,
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "tenant could not be found",
  );

  rerender(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => Promise.reject(new Error("offline"))}
    />,
  );
  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Call definitions could not be loaded",
    ),
  );
});

test("loads the approved services page directly and exposes all tenant destinations", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi.fn(() => response(serviceDirectory("AAAAAAAAAAAAAAAA")));

  render(<AdminApp csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(
    await screen.findByRole("heading", { name: "Services" }),
  ).toBeVisible();
  expect(screen.getAllByText("Google AI Studio")).not.toHaveLength(0);
  expect(screen.getByRole("link", { name: "Call definitions" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Calls" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Services" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/services",
    expect.objectContaining({ signal: expect.any(AbortSignal) }),
  );
});

test("submits write-only credential values with CSRF and updates metadata after success", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi
    .fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(
      () => response(serviceDirectory("AAAAAAAAAAAAAAAA", false)),
    )
    .mockImplementationOnce(() =>
      response(serviceDirectory("AAAAAAAAAAAAAAAA", false)),
    )
    .mockImplementationOnce(
      (_input?: RequestInfo | URL, init?: RequestInit) => {
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
      },
    );

  render(<AdminApp csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("No services yet")).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save credential" }));

  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(screen.getByText("Credential stored.")).toBeVisible();
  expect(screen.getAllByText("Google AI Studio")).not.toHaveLength(0);
  expect(screen.queryByDisplayValue("private-value")).not.toBeInTheDocument();
});

test("replaces credentials from the edit dialog and refreshes their safe preview", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  const fetchImpl = vi
    .fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>()
    .mockImplementationOnce(() =>
      response(serviceDirectory("AAAAAAAAAAAAAAAA")),
    )
    .mockImplementationOnce((input, init) => {
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
    });

  render(<AdminApp csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("****8c4a")).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Edit Google AI Studio credentials" }),
  );
  expect(screen.getByLabelText("Provider")).toBeDisabled();
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "replacement-7f2b" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Update credential" }));

  expect(await screen.findByText("****7f2b")).toBeVisible();
  expect(screen.queryByText("****8c4a")).not.toBeInTheDocument();
});

test("ignores a stale credential submission after leaving the tenant services page", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  const expired = vi.fn();
  let resolveCreate: ((value: Response) => void) | undefined;
  const pendingCreate = new Promise<Response>((resolve) => {
    resolveCreate = resolve;
  });
  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "POST") return pendingCreate;
    const url = String(input);
    if (url.includes("/definitions")) {
      return response(
        definitionPage(
          "AAAAAAAAAAAAAAAA",
          "Example tenant",
          "Current definition",
        ),
      );
    }
    return response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
  });

  render(
    <AdminApp
      csrfToken="csrf-token"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save credential" }));

  window.history.pushState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/definitions",
  );
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current definition")).toBeVisible();

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
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  let resolveCreate: ((value: Response) => void) | undefined;
  const pendingCreate = new Promise<Response>((resolve) => {
    resolveCreate = resolve;
  });
  const fetchImpl = vi.fn((_input: RequestInfo | URL, init?: RequestInit) =>
    init?.method === "POST"
      ? pendingCreate
      : response(serviceDirectory("AAAAAAAAAAAAAAAA", false)),
  );

  render(<AdminApp csrfToken="csrf-token" fetchImpl={fetchImpl} />);
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "first-secret" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save credential" }));
  fireEvent.click(
    screen.getByRole("button", { name: "Close credential setup" }),
  );

  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
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

  expect(screen.getByRole("dialog", { name: "Add credential" })).toBeVisible();
  expect(screen.getByLabelText("API key")).toHaveValue("second-secret");
});

test("presents service load, duplicate, and expired-session outcomes truthfully", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
  const expired = vi.fn();
  const unavailableView = render(
    <AdminApp
      csrfToken="csrf-token"
      fetchImpl={() => Promise.reject(new Error("offline"))}
      onSessionExpired={expired}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Services could not be loaded",
  );
  unavailableView.unmount();

  const fetchImpl = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "POST") {
      return response({ error: { code: "credential_already_exists" } }, 409);
    }
    return response(serviceDirectory("AAAAAAAAAAAAAAAA", false));
  });

  render(
    <AdminApp
      csrfToken="csrf-token"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );
  expect(await screen.findByText("No services yet")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "private-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save credential" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("already exists");

  cleanup();
  render(
    <AdminApp
      csrfToken="csrf-token"
      fetchImpl={() => response({}, 401)}
      onSessionExpired={expired}
    />,
  );
  await waitFor(() => expect(expired).toHaveBeenCalledOnce());
});

test("rejects a service directory for a different tenant", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );

  render(
    <AdminApp
      csrfToken="csrf-token"
      fetchImpl={() => response(serviceDirectory("BBBBBBBBBBBBBBBB"))}
    />,
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Services could not be loaded",
  );
  expect(screen.queryByText("Credential stored")).not.toBeInTheDocument();
});
