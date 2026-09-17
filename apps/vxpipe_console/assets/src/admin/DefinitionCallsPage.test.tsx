import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { DefinitionCallsPage } from "./DefinitionCallsPage";
import { DefinitionCallsStory } from "./DefinitionCallsStory";
import type { DefinitionCallsPageState } from "./callTypes";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

const populated: DefinitionCallsPageState = {
  status: "ready",
  tenant: { key: "tn_demo_01", name: "Demo workspace" },
  definitions: [
    { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    { id: "appointment-reminders", name: "Appointment reminders" },
  ],
  selectedDefinitionId: null,
  calls: [
    {
      id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
      definitionId: "delivery-rescheduling",
      definitionName: "Delivery rescheduling",
      definitionRevision: 3,
      state: "running",
      createdAt: "2026-09-17T02:20:00.000Z",
      startedAt: "2026-09-17T02:20:03.000Z",
      endedAt: null,
      terminalReason: null,
      archiveState: "unconfirmed",
    },
    {
      id: "018f27a2-51d5-77c9-a44f-e5c648bf8495",
      definitionId: "delivery-rescheduling",
      definitionName: "Delivery rescheduling",
      definitionRevision: 2,
      state: "ended",
      createdAt: "2026-09-16T08:00:00.000Z",
      startedAt: "2026-09-16T08:00:02.000Z",
      endedAt: "2026-09-16T08:01:32.000Z",
      terminalReason: null,
      archiveState: "complete",
    },
    {
      id: "018f2791-f803-781c-9e96-35cc46d612cc",
      definitionId: "delivery-rescheduling",
      definitionName: "Delivery rescheduling",
      definitionRevision: 4,
      state: "failed",
      createdAt: "2026-09-16T06:10:00.000Z",
      startedAt: null,
      endedAt: "2026-09-16T06:10:01.000Z",
      terminalReason: "session_start_failed",
      archiveState: "incomplete",
    },
  ],
  pagination: {
    label: "1–3 of 3",
    hasPrevious: false,
    hasNext: true,
  },
};

test("shows tenant navigation and real call links", () => {
  const selectCall = vi.fn();

  render(<DefinitionCallsPage onSelectCall={selectCall} state={populated} />);

  expect(screen.getByRole("heading", { name: "Calls" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute(
    "href",
    "/admin",
  );
  expect(screen.getByRole("link", { name: "Demo workspace" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01",
  );
  expect(screen.getByRole("link", { name: "Call definitions" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/definitions",
  );
  expect(screen.getByRole("link", { name: "Calls" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getByRole("link", { name: "Services" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/services",
  );
  expect(screen.queryByText(/Across all revisions/i)).not.toBeInTheDocument();
  expect(screen.queryByText(/published r3/i)).not.toBeInTheDocument();

  const call = screen.getByRole("link", {
    name: /open call 018f27cb/i,
  });
  expect(call).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01/calls/018f27cb-6f87-7d1c-a61f-8873cb667342",
  );
  fireEvent.click(call);
  expect(selectCall).toHaveBeenCalledWith(
    "018f27cb-6f87-7d1c-a61f-8873cb667342",
  );
});

test("selects and resets a definition filter through injected actions", () => {
  const selectDefinition = vi.fn();

  const view = render(
    <DefinitionCallsPage
      onSelectDefinition={selectDefinition}
      state={populated}
    />,
  );

  fireEvent.change(screen.getByRole("combobox", { name: "Call definition" }), {
    target: { value: "delivery-rescheduling" },
  });
  expect(selectDefinition).toHaveBeenCalledWith("delivery-rescheduling");

  view.rerender(
    <DefinitionCallsPage
      onSelectDefinition={selectDefinition}
      state={{ ...populated, selectedDefinitionId: "delivery-rescheduling" }}
    />,
  );
  fireEvent.click(screen.getByRole("button", { name: "Show all calls" }));
  expect(selectDefinition).toHaveBeenLastCalledWith(null);
});

test("keeps valid empty filters distinct from unknown filters", () => {
  const { rerender } = render(
    <DefinitionCallsPage
      state={{
        ...populated,
        selectedDefinitionId: "appointment-reminders",
        calls: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByText("No matching calls")).toBeVisible();

  rerender(
    <DefinitionCallsPage
      state={{
        ...populated,
        selectedDefinitionId: "missing-definition",
        calls: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "This call definition is not available",
  );
});

test("shows lifecycle, revision, archive, duration, and failure information", () => {
  render(<DefinitionCallsPage state={populated} />);

  expect(screen.getByText("Ongoing")).toBeVisible();
  expect(screen.getByText("Ended")).toBeVisible();
  expect(screen.getByText("Failed")).toBeVisible();
  expect(screen.getByText("Partial")).toBeVisible();
  expect(screen.getByText("1m 30s")).toBeVisible();
  expect(screen.getAllByText("Session start failed")).not.toHaveLength(0);
  expect(screen.getByText("v4")).toBeVisible();
});

test("does not present a prepared call's creation time as its start time", () => {
  const createdAt = "2026-09-15T09:30:00.000Z";
  const { container } = render(
    <DefinitionCallsPage
      state={{
        ...populated,
        calls: [
          {
            id: "018f2708-76d2-72f5-885c-d2d62a8a8ea1",
            definitionId: "delivery-rescheduling",
            definitionName: "Delivery rescheduling",
            definitionRevision: 1,
            state: "prepared",
            createdAt,
            startedAt: null,
            endedAt: null,
            terminalReason: null,
            archiveState: "unconfirmed",
          },
        ],
      }}
    />,
  );

  expect(container.querySelector(`time[datetime="${createdAt}"]`)).toBeNull();
  expect(screen.getByText(/created /i)).toBeVisible();
});

test("keeps empty and unavailable call results distinct", () => {
  const { rerender } = render(
    <DefinitionCallsPage
      state={{ ...populated, calls: [], pagination: null }}
    />,
  );

  expect(screen.getByText("No calls yet")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();

  rerender(
    <DefinitionCallsPage
      state={{
        status: "unavailable",
        tenant: populated.tenant,
        definitions: populated.definitions,
        selectedDefinitionId: null,
        message: "Calls could not be loaded.",
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "Calls could not be loaded.",
  );
  expect(screen.queryByText("No calls yet")).not.toBeInTheDocument();
});

test("call pagination invokes only valid actions", () => {
  const previous = vi.fn();
  const next = vi.fn();

  render(
    <DefinitionCallsPage
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

test("loading removes stale call actions", () => {
  render(
    <DefinitionCallsPage
      state={{
        status: "loading",
        tenant: populated.tenant,
        definitions: populated.definitions,
        selectedDefinitionId: null,
      }}
    />,
  );

  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(screen.queryByRole("link", { name: /^open call/i })).not.toBeInTheDocument();
});

test("the paginated call story reaches its advertised final page", () => {
  render(<DefinitionCallsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(screen.getByText("9–12 of 12")).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("pagination preserves lifecycle timestamps and ended-call duration", () => {
  render(<DefinitionCallsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  const rows = screen.getAllByRole("link", { name: /^open call/i });

  expect(rows[1]).toHaveTextContent("1m 30s");
  expect(rows[2].querySelector("time")).toBeNull();
  expect(rows[3].querySelector("time")).toBeNull();
});

test("call story records call and breadcrumb destinations without replacing the preview", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-definition-calls--populated",
  );
  render(<DefinitionCallsStory scenario="populated" theme="dark" />);

  fireEvent.click(screen.getByRole("link", { name: /open call 018f27cb/i }));
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls/018f27cb-6f87-7d1c-a61f-8873cb667342",
  );

  fireEvent.click(screen.getByRole("link", { name: "Demo workspace" }));
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/definitions");
});

test("call story keeps the selected definition in its URL and visible results", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=admin-calls--populated",
  );
  render(<DefinitionCallsStory scenario="populated" theme="dark" />);

  fireEvent.change(screen.getByRole("combobox", { name: "Call definition" }), {
    target: { value: "appointment-reminders" },
  });

  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?definition_id=appointment-reminders",
  );
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(2);
});

test("call story clears stale pagination when its definition filter changes", () => {
  render(<DefinitionCallsStory scenario="paginated" theme="dark" />);

  fireEvent.change(screen.getByRole("combobox", { name: "Call definition" }), {
    target: { value: "appointment-reminders" },
  });

  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(2);
  expect(screen.queryByRole("button", { name: "Next page" })).not.toBeInTheDocument();

  fireEvent.click(screen.getByRole("button", { name: "Show all calls" }));
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(9);
  expect(screen.queryByRole("button", { name: "Next page" })).not.toBeInTheDocument();
});
