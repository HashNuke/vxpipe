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
