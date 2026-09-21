import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("@vxpipe/react", () => ({
  CallConsole: ({ header }: { header?: ReactNode }) => (
    <div>
      {header}
      Reusable call console
    </div>
  ),
}));

import { AdminJourneyStory } from "./AdminJourneyStory";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

test("links the tenant directory to call specs and back", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));

  expect(
    screen.getByRole("heading", { name: "Call specs" }),
  ).toBeVisible();
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/call-specs");

  fireEvent.click(
    screen.getByRole("link", {
      name: /view 5 calls for delivery rescheduling/i,
    }),
  );
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?call_spec_id=delivery-rescheduling",
  );
  expect(screen.getByRole("heading", { name: "Calls" })).toBeVisible();
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(5);

  const call = screen.getByRole("link", { name: /open call 018f27cb/i });
  expect(call).toHaveAttribute("target", "_blank");
  fireEvent.click(call);
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?call_spec_id=delivery-rescheduling",
  );
  expect(screen.getByRole("heading", { name: "Calls" })).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: "Demo workspace" }));
  expect(
    screen.getByRole("heading", { name: "Call specs" }),
  ).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(window.location.hash).toBe("#/admin");
});

test("keeps a non-default call spec context when a call route is reloaded", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  const view = render(<AdminJourneyStory theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));
  fireEvent.click(
    screen.getByRole("link", {
      name: /view 2 calls for appointment reminders/i,
    }),
  );

  expect(screen.queryByText(/Across all revisions/i)).not.toBeInTheDocument();
  expect(screen.queryByText("r3")).not.toBeInTheDocument();
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(2);

  const destination = screen
    .getAllByRole("link", { name: /open call/i })[0]
    .getAttribute("href")!;
  view.unmount();
  window.history.replaceState({}, "", destination);
  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("heading", { name: "Call details" })).toBeVisible();
  expect(screen.getByText("Appointment reminders")).toBeVisible();
  const callSpec = screen.getByRole("link", {
    name: "Appointment reminders",
  });
  expect(
    new URL(callSpec.getAttribute("href")!, window.location.origin).hash,
  ).toBe(
    "#/admin/tenants/tn_demo_01/calls?call_spec_id=appointment-reminders",
  );
  expect(screen.queryByText("Delivery rescheduling")).not.toBeInTheDocument();
});

test("does not substitute the default call spec for an unknown call route", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-full-journey#/admin/tenants/tn_demo_01/calls/unknown-call",
  );

  render(<AdminJourneyStory theme="dark" />);

  expect(
    screen.getByRole("heading", { name: "Call unavailable" }),
  ).toBeVisible();
  expect(screen.queryByText("Delivery rescheduling")).not.toBeInTheDocument();
  expect(screen.queryByText(/revision r0/i)).not.toBeInTheDocument();

  expect(screen.getByText("Demo workspace")).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Demo workspace" })).toBeVisible();
});

test("moves between sibling call specs and all tenant calls", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  render(<AdminJourneyStory theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));
  fireEvent.click(screen.getByRole("link", { name: "Calls" }));

  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/calls");
  expect(screen.getByRole("combobox", { name: "Call spec" })).toHaveTextContent(
    "All call specs",
  );
  expect(
    screen.getAllByRole("link", { name: /^open call/i }).length,
  ).toBeGreaterThan(5);

  fireEvent.click(screen.getByRole("link", { name: "Call specs" }));
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/call-specs");
});

test("reaches services through the tenant workspace", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  render(<AdminJourneyStory theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));
  fireEvent.click(screen.getByRole("link", { name: "Services" }));

  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/services");
  expect(screen.getByRole("heading", { name: "Services" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Add credential" })).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  fireEvent.change(screen.getByLabelText("Provider"), {
    target: { value: "zenmux" },
  });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "valid-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByRole("status")).toHaveTextContent("Credential stored");
  expect(
    screen.getByRole("button", { name: "Edit Zenmux credentials" }),
  ).toBeVisible();

  fireEvent.click(screen.getByRole("button", { name: "Add credential" }));
  expect(screen.getByLabelText("API key")).toHaveValue("");
  expect(
    within(screen.getByRole("dialog")).queryByText("Credential stored."),
  ).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("resets service state when the tenant route changes", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-full-journey#/admin/tenants/tn_demo_01/services",
  );
  render(<AdminJourneyStory theme="dark" />);
  expect(screen.getByText("Demo workspace")).toBeVisible();

  window.history.pushState(
    {},
    "",
    "#/admin/tenants/tn_other_workspace/services",
  );
  fireEvent(window, new PopStateEvent("popstate"));

  expect(screen.getByText("tn_other_workspace")).toBeVisible();
  expect(screen.queryByText("Demo workspace")).not.toBeInTheDocument();
});
