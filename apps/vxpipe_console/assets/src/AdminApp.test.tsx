import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { AdminApp } from "./AdminApp";

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

const definitionPage = (tenantKey: string, tenantName: string, definitionName: string) => ({
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

test("loads the approved tenant page with a CSRF-protected sign-out action", async () => {
  const fetchImpl = vi.fn(() => response(tenantPage(1)));
  const view = render(<AdminApp csrfToken="csrf-test-token" fetchImpl={fetchImpl} />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Sign out" })).toBeVisible();
  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/admin/api/tenants?page=1", {
    headers: { accept: "application/json" },
    signal: expect.any(AbortSignal),
  });
  expect(view.container.querySelector('form[action="/auth/logout"]')).toHaveAttribute(
    "method",
    "post",
  );
  expect(view.container.querySelector('input[name="_csrf_token"]')).toHaveValue(
    "csrf-test-token",
  );
});

test("shows empty, unavailable, and expired-session outcomes truthfully", async () => {
  const expired = vi.fn();
  const { rerender } = render(
    <AdminApp
      csrfToken="csrf"
      fetchImpl={() => response({ tenants: [], pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 } })}
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

  expect(await screen.findByRole("alert")).toHaveTextContent("Tenant data could not be loaded");

  rerender(
    <AdminApp csrfToken="csrf" fetchImpl={() => response({}, 401)} onSessionExpired={expired} />,
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
    .mockImplementationOnce(() => response(tenantPage(2, "Second page tenant")));

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState({}, "", "/admin?page=2");
  window.dispatchEvent(new PopStateEvent("popstate"));

  expect(await screen.findByText("Second page tenant")).toBeVisible();
  resolveFirst?.(await response(tenantPage(1, "Stale tenant")));

  await waitFor(() => expect(screen.queryByText("Stale tenant")).not.toBeInTheDocument());

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
    <AdminApp csrfToken="csrf" fetchImpl={fetchImpl} onSessionExpired={expired} />,
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
    .mockImplementationOnce(() => response({ error: { code: "invalid_page" } }, 422));

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Example tenant")).toBeVisible();
  expect(window.location.pathname + window.location.search).toBe("/admin");
  expect(fetchImpl).toHaveBeenNthCalledWith(1, "/admin/api/tenants?page=999", expect.any(Object));
  expect(fetchImpl).toHaveBeenNthCalledWith(2, "/admin/api/tenants?page=1", expect.any(Object));
});

test("opens a tenant's approved definitions page and canonicalizes the workspace URL", async () => {
  const fetchImpl = vi.fn((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.startsWith("/admin/api/tenants?")) return response(tenantPage(1));
    return response(definitionPage("tenant-1-0", "Example tenant", "Delivery rescheduling"));
  });

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  fireEvent.click(await screen.findByRole("link", { name: "Open Example tenant" }));

  expect(await screen.findByRole("heading", { name: "Call definitions" })).toBeVisible();
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
  expect(window.location.pathname).toBe("/admin/tenants/tenant-1-0/definitions");
  expect(screen.queryByRole("link", { name: "Calls" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Services" })).not.toBeInTheDocument();
  expect(screen.getByText("5")).toBeVisible();
  expect(
    screen.queryByRole("link", { name: "View 5 calls for Delivery rescheduling" }),
  ).not.toBeInTheDocument();
});

test("redirects a tenant workspace root to definitions on direct load", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA");
  const fetchImpl = vi.fn(() =>
    response(definitionPage("AAAAAAAAAAAAAAAA", "Example tenant", "Direct definition")),
  );

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Direct definition")).toBeVisible();
  expect(window.location.pathname).toBe("/admin/tenants/AAAAAAAAAAAAAAAA/definitions");
});

test("ignores an obsolete definition response after switching tenants", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/definitions");
  let resolveFirst: ((value: Response) => void) | undefined;
  const first = new Promise<Response>((resolve) => {
    resolveFirst = resolve;
  });
  const fetchImpl = vi
    .fn(() => response(definitionPage("BBBBBBBBBBBBBBBB", "Tenant B", "Current definition")))
    .mockImplementationOnce(() => first);

  render(<AdminApp csrfToken="csrf" fetchImpl={fetchImpl} />);

  window.history.pushState({}, "", "/admin/tenants/BBBBBBBBBBBBBBBB/definitions");
  window.dispatchEvent(new PopStateEvent("popstate"));
  expect(await screen.findByText("Current definition")).toBeVisible();

  await act(async () => {
    resolveFirst?.(
      await response(definitionPage("AAAAAAAAAAAAAAAA", "Tenant A", "Stale definition")),
    );
    await first;
  });

  expect(screen.queryByText("Stale definition")).not.toBeInTheDocument();
});

test("keeps empty, missing, and unavailable definition states distinct", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/definitions");
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
  expect(await screen.findByRole("alert")).toHaveTextContent("tenant could not be found");

  rerender(
    <AdminApp csrfToken="csrf" fetchImpl={() => Promise.reject(new Error("offline"))} />,
  );
  await waitFor(() =>
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Call definitions could not be loaded",
    ),
  );
});
