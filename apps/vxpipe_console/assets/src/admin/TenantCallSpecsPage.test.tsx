import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { TenantCallSpecsPage } from "./TenantCallSpecsPage";
import { TenantCallSpecsStory } from "./TenantCallSpecsStory";
import type { TenantCallSpecsPageState } from "./callSpecTypes";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

const populated: TenantCallSpecsPageState = {
  status: "ready",
  tenant: { key: "tn_demo_01", name: "Demo workspace" },
  callSpecs: [
    {
      id: "delivery-rescheduling",
      name: "Delivery rescheduling",
      latestRevision: 4,
      publishedRevision: 3,
      callCount: 5,
      updatedAt: "2026-09-16T08:40:00.000Z",
    },
    {
      id: "appointment-reminders",
      name: "Appointment reminders",
      latestRevision: 2,
      publishedRevision: 2,
      callCount: 2,
      updatedAt: "2026-09-15T10:20:00.000Z",
    },
    {
      id: "returns-intake",
      name: null,
      latestRevision: 1,
      publishedRevision: null,
      callCount: 1,
      updatedAt: "2026-09-14T03:15:00.000Z",
    },
  ],
  pagination: {
    label: "1–3 of 3",
    hasPrevious: false,
    hasNext: true,
  },
};

test("keeps tenant context and real call spec links visible", () => {
  const selectCallSpec = vi.fn();

  render(
    <TenantCallSpecsPage
      onSelectCallSpec={selectCallSpec}
      state={populated}
    />,
  );

  expect(screen.getByRole("heading", { name: "Call specs" })).toBeVisible();
  expect(screen.getByRole("columnheader", { name: "Name" })).toBeVisible();
  expect(screen.getByRole("columnheader", { name: "Version" })).toBeVisible();
  expect(screen.getByRole("columnheader", { name: "Calls" })).toBeVisible();
  expect(screen.queryByText("CallSpec")).not.toBeInTheDocument();
  expect(screen.queryByText("Revision")).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute(
    "href",
    "/admin",
  );
  expect(screen.getByText("Demo workspace")).toBeVisible();
  expect(screen.getByRole("link", { name: "Call specs" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getByRole("link", { name: "Calls" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/calls",
  );

  const callSpecCalls = screen.getByRole("link", {
    name: /view 5 calls for delivery rescheduling/i,
  });
  expect(callSpecCalls).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/calls?call_spec_id=delivery-rescheduling",
  );

  fireEvent.click(callSpecCalls);
  expect(selectCallSpec).toHaveBeenCalledWith("delivery-rescheduling");
});

test("distinguishes published, draft changes, and unpublished call specs", () => {
  render(<TenantCallSpecsPage state={populated} />);

  expect(screen.getByText("Published")).toBeVisible();
  expect(screen.getByText("Draft changes")).toBeVisible();
  expect(screen.getByText("Draft")).toBeVisible();
  expect(
    screen.getByRole("link", { name: "View 1 calls for returns-intake" }),
  ).toBeVisible();
});

test("keeps empty and unavailable call spec results distinct", () => {
  const { rerender } = render(
    <TenantCallSpecsPage
      state={{
        status: "ready",
        tenant: populated.tenant,
        callSpecs: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByText("No call specs yet")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();

  rerender(
    <TenantCallSpecsPage
      state={{
        status: "unavailable",
        tenant: populated.tenant,
        message: "Call specs could not be loaded.",
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "Call specs could not be loaded.",
  );
  expect(screen.queryByText("No call specs yet")).not.toBeInTheDocument();
});

test("call spec pagination invokes only valid actions", () => {
  const previous = vi.fn();
  const next = vi.fn();

  render(
    <TenantCallSpecsPage
      onNextPage={next}
      onPreviousPage={previous}
      state={populated}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Previous page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(previous).not.toHaveBeenCalled();
  expect(next).toHaveBeenCalledOnce();
});

test("loading removes stale call spec actions", () => {
  render(
    <TenantCallSpecsPage
      state={{ status: "loading", tenant: populated.tenant }}
    />,
  );

  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(screen.queryByRole("link", { name: /^view .* calls for /i })).not.toBeInTheDocument();
});

test("the paginated call spec story reaches its advertised final page", () => {
  render(
    <TenantCallSpecsStory scenario="paginated" theme="dark" />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(screen.getByText("9–12 of 12")).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("call spec story links record forward and back destinations without replacing the preview", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-tenant-call-specs--populated",
  );
  render(<TenantCallSpecsStory scenario="populated" theme="dark" />);

  fireEvent.click(
    screen.getByRole("link", {
      name: /view 5 calls for delivery rescheduling/i,
    }),
  );
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?call_spec_id=delivery-rescheduling",
  );

  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  expect(window.location.hash).toBe("#/admin");
});

test("offers new and edit links while preserving the separate calls link", () => {
  const navigate = vi.fn();
  render(<TenantCallSpecsPage state={populated} onEditCallSpec={navigate} onNewCallSpec={() => navigate("new")} />);
  expect(screen.getByRole("link", { name: "New call spec" })).toHaveAttribute("href", "/admin/tenants/tn_demo_01/call-specs/new");
  const edit = screen.getByRole("link", { name: "Delivery rescheduling" });
  expect(edit).toHaveAttribute("href", "/admin/tenants/tn_demo_01/call-specs/delivery-rescheduling");
  fireEvent.click(edit); expect(navigate).toHaveBeenCalledWith("delivery-rescheduling");
  expect(screen.getByRole("link", { name: "View 5 calls for Delivery rescheduling" })).toHaveAttribute("href", "/admin/tenants/tn_demo_01/calls?call_spec_id=delivery-rescheduling");
});
