import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("@vxpipe/react", () => ({
  CallConsole: () => <div>Reusable call console</div>,
}));

import { AdminJourneyStory } from "./AdminJourneyStory";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

test("links the tenant directory to definitions and back", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));

  expect(
    screen.getByRole("heading", { name: "Call definitions" }),
  ).toBeVisible();
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01");

  fireEvent.click(
    screen.getByRole("link", { name: /open delivery rescheduling/i }),
  );
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/definitions/delivery-rescheduling",
  );
  expect(screen.getByRole("heading", { name: "Calls" })).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: /open call 018f27cb/i }));
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls/018f27cb-6f87-7d1c-a61f-8873cb667342",
  );
  expect(
    within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText(
      "Call details",
    ),
  ).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: "Demo workspace" }));
  expect(
    screen.getByRole("heading", { name: "Call definitions" }),
  ).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(window.location.hash).toBe("#/admin");
});

test("keeps a non-default definition context when a call route is reloaded", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  const view = render(<AdminJourneyStory theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));
  fireEvent.click(
    screen.getByRole("link", { name: /open appointment reminders/i }),
  );

  expect(screen.queryByText(/Across all revisions/i)).not.toBeInTheDocument();
  expect(screen.queryByText("r3")).not.toBeInTheDocument();

  fireEvent.click(screen.getAllByRole("link", { name: /open call/i })[0]);
  expect(
    within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText(
      "Call details",
    ),
  ).toBeVisible();
  expect(screen.getByRole("link", { name: "Appointment reminders" })).toBeVisible();

  view.unmount();
  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("link", { name: "Appointment reminders" })).toBeVisible();
  expect(screen.queryByText("Delivery rescheduling")).not.toBeInTheDocument();
});

test("does not substitute the default definition for an unknown call route", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-full-journey#/admin/tenants/tn_demo_01/calls/unknown-call",
  );

  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("heading", { name: "Call unavailable" })).toBeVisible();
  expect(screen.queryByText("Delivery rescheduling")).not.toBeInTheDocument();
  expect(screen.queryByText(/revision r0/i)).not.toBeInTheDocument();

  fireEvent.click(screen.getByRole("link", { name: "Demo workspace" }));
  expect(screen.getByRole("heading", { name: "Call definitions" })).toBeVisible();
});
