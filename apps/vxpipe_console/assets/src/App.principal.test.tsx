import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { App } from "./App";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});

const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

const tenantDirectory = {
  items: [{ tenant_key: "acme_demo_000001", name: "Acme", created_at: "2026-09-17T01:00:00Z" }],
  pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
};

const callSpecPage = {
  tenant: { key: "acme_demo_000001", name: "Acme" },
  call_specs: [],
  pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
};

const serviceDirectory = {
  tenant: { key: "acme_demo_000001", name: "Acme" },
  truncated: false,
  credentials: [],
  telephony_services: [],
};

function pendingSessionFetch(path: string) {
  if (path.startsWith("/admin/api/navigation")) return new Promise<Response>(() => undefined);
  if (path === "/admin/api/session") return new Promise<Response>(() => undefined);
  if (path.startsWith("/api/tenants?")) return response(tenantDirectory);
  if (path.includes("/call-specs")) return response(callSpecPage);
  if (path.endsWith("/services") || path.includes("/service-bindings"))
    return response(serviceDirectory);
  return response({}, 404);
}

test("loading principal hides Platform services until authority is known", async () => {
  window.history.replaceState({}, "", "/admin");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    pendingSessionFetch(String(input)),
  );
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Loading workspace…")).toBeVisible();
  expect(screen.getByRole("button", { name: "Logout" })).toBeVisible();
  expect(
    screen.queryByRole("link", { name: "Platform services" }),
  ).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Account" })).not.toBeInTheDocument();
});

test("loading principal hides call-spec creation and Services destination", async () => {
  window.history.replaceState({}, "", "/admin/tenants/acme_demo_000001/call-specs");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    pendingSessionFetch(String(input)),
  );
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Loading workspace…")).toBeVisible();
  expect(screen.queryByText("No call specs yet")).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "New call spec" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Services" })).not.toBeInTheDocument();
  expect(
    screen.queryByRole("link", { name: "Platform services" }),
  ).not.toBeInTheDocument();
});

test("loading principal hides service connection controls", async () => {
  window.history.replaceState({}, "", "/admin/tenants/acme_demo_000001/services");
  const fetchImpl = vi.fn((input: RequestInfo | URL) =>
    pendingSessionFetch(String(input)),
  );
  render(<App csrfToken="csrf-token" fetchImpl={fetchImpl} />);

  expect(await screen.findByText("Loading workspace…")).toBeVisible();
  expect(screen.queryByText("No services yet")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: "Connect a service" }),
  ).not.toBeInTheDocument();
});
