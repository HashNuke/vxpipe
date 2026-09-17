import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { TenantsPage } from "./TenantsPage";
import { TenantsStory } from "./TenantsStory";
import type { TenantsPageState } from "./tenantTypes";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

const populated: TenantsPageState = {
  status: "ready",
  tenants: [
    {
      key: "tn_demo_01",
      name: "Demo workspace",
      createdAt: "2026-09-14T09:30:00.000Z",
    },
  ],
  pagination: {
    label: "1–1 of 1",
    hasPrevious: false,
    hasNext: true,
  },
};

test("renders stable tenant identity as a real admin link", () => {
  const selectTenant = vi.fn();

  render(<TenantsPage state={populated} onSelectTenant={selectTenant} />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByText("Demo workspace")).toBeVisible();
  expect(screen.getByText("tn_demo_01")).toBeVisible();

  const link = screen.getByRole("link", { name: /open demo workspace/i });
  expect(link).toHaveAttribute("href", "/admin/tenants/tn_demo_01");

  fireEvent.click(link);
  expect(selectTenant).toHaveBeenCalledWith("tn_demo_01");
});

test("leaves modified tenant-link clicks to the browser", () => {
  const selectTenant = vi.fn();

  render(<TenantsPage state={populated} onSelectTenant={selectTenant} />);
  window.addEventListener("click", (event) => event.preventDefault(), {
    once: true,
  });

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }), {
    metaKey: true,
  });

  expect(selectTenant).not.toHaveBeenCalled();
});

test("keeps empty and unavailable results visibly distinct", () => {
  const { rerender } = render(
    <TenantsPage state={{ status: "ready", tenants: [], pagination: null }} />,
  );

  expect(screen.getByText("No tenants yet")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();

  rerender(
    <TenantsPage
      state={{
        status: "unavailable",
        message: "Tenant data could not be loaded.",
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "Tenant data could not be loaded.",
  );
  expect(screen.queryByText("No tenants yet")).not.toBeInTheDocument();
});

test("exposes only valid pagination actions", () => {
  const previous = vi.fn();
  const next = vi.fn();

  render(
    <TenantsPage
      state={populated}
      onPreviousPage={previous}
      onNextPage={next}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Previous page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(previous).not.toHaveBeenCalled();
  expect(next).toHaveBeenCalledOnce();
});

test("announces the loading state without retaining tenant actions", () => {
  render(<TenantsPage state={{ status: "loading" }} />);

  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(screen.queryByRole("link")).not.toBeInTheDocument();
});

test("the paginated story reaches its advertised final page", () => {
  render(<TenantsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(screen.getByText("9–12 of 12")).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("story selection keeps the preview document reloadable", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-tenants--populated");
  render(<TenantsStory scenario="populated" theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));

  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01");
});
