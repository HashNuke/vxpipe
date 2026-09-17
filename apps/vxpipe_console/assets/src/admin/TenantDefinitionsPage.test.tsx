import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { TenantDefinitionsPage } from "./TenantDefinitionsPage";
import { TenantDefinitionsStory } from "./TenantDefinitionsStory";
import type { TenantDefinitionsPageState } from "./definitionTypes";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

const populated: TenantDefinitionsPageState = {
  status: "ready",
  tenant: { key: "tn_demo_01", name: "Demo workspace" },
  definitions: [
    {
      id: "delivery-rescheduling",
      name: "Delivery rescheduling",
      latestRevision: 4,
      publishedRevision: 3,
      updatedAt: "2026-09-16T08:40:00.000Z",
    },
    {
      id: "appointment-reminders",
      name: "Appointment reminders",
      latestRevision: 2,
      publishedRevision: 2,
      updatedAt: "2026-09-15T10:20:00.000Z",
    },
    {
      id: "returns-intake",
      name: null,
      latestRevision: 1,
      publishedRevision: null,
      updatedAt: "2026-09-14T03:15:00.000Z",
    },
  ],
  pagination: {
    label: "1–3 of 3",
    hasPrevious: false,
    hasNext: true,
  },
};

test("keeps tenant context and real definition links visible", () => {
  const selectDefinition = vi.fn();

  render(
    <TenantDefinitionsPage
      onSelectDefinition={selectDefinition}
      state={populated}
    />,
  );

  expect(screen.getByRole("heading", { name: "Call definitions" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute(
    "href",
    "/admin",
  );
  expect(screen.getByText("Demo workspace")).toBeVisible();
  expect(screen.getByRole("link", { name: "Call definitions" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getByRole("link", { name: "Calls" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/calls",
  );

  const definition = screen.getByRole("link", {
    name: /open delivery rescheduling/i,
  });
  expect(definition).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/calls?definition_id=delivery-rescheduling",
  );

  fireEvent.click(definition);
  expect(selectDefinition).toHaveBeenCalledWith("delivery-rescheduling");
});

test("distinguishes published, draft changes, and unpublished definitions", () => {
  render(<TenantDefinitionsPage state={populated} />);

  expect(screen.getByText("Published")).toBeVisible();
  expect(screen.getByText("Draft changes")).toBeVisible();
  expect(screen.getByText("Draft")).toBeVisible();
  expect(
    screen.getByRole("link", { name: "Open returns-intake" }),
  ).toBeVisible();
});

test("keeps empty and unavailable definition results distinct", () => {
  const { rerender } = render(
    <TenantDefinitionsPage
      state={{
        status: "ready",
        tenant: populated.tenant,
        definitions: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByText("No call definitions yet")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();

  rerender(
    <TenantDefinitionsPage
      state={{
        status: "unavailable",
        tenant: populated.tenant,
        message: "Call definitions could not be loaded.",
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "Call definitions could not be loaded.",
  );
  expect(screen.queryByText("No call definitions yet")).not.toBeInTheDocument();
});

test("definition pagination invokes only valid actions", () => {
  const previous = vi.fn();
  const next = vi.fn();

  render(
    <TenantDefinitionsPage
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

test("loading removes stale definition actions", () => {
  render(
    <TenantDefinitionsPage
      state={{ status: "loading", tenant: populated.tenant }}
    />,
  );

  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(screen.queryByRole("link", { name: /^open /i })).not.toBeInTheDocument();
});

test("the paginated definition story reaches its advertised final page", () => {
  render(
    <TenantDefinitionsStory scenario="paginated" theme="dark" />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(screen.getByText("9–12 of 12")).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("definition story links record forward and back destinations without replacing the preview", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-tenant-definitions--populated",
  );
  render(<TenantDefinitionsStory scenario="populated" theme="dark" />);

  fireEvent.click(
    screen.getByRole("link", { name: /open delivery rescheduling/i }),
  );
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?definition_id=delivery-rescheduling",
  );

  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  expect(window.location.hash).toBe("#/admin");
});
