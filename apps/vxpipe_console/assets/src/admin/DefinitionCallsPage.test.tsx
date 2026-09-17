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
  definition: {
    id: "delivery-rescheduling",
    name: "Delivery rescheduling",
    latestRevision: 4,
    publishedRevision: 3,
  },
  calls: [
    {
      id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
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

test("retains tenant and definition context around real call links", () => {
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
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
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

test("shows lifecycle, revision, archive, duration, and failure information", () => {
  render(<DefinitionCallsPage state={populated} />);

  expect(screen.getByText("Ongoing")).toBeVisible();
  expect(screen.getByText("Ended")).toBeVisible();
  expect(screen.getByText("Failed")).toBeVisible();
  expect(screen.getByText("Partial")).toBeVisible();
  expect(screen.getByText("1m 30s")).toBeVisible();
  expect(screen.getAllByText("Session start failed")).not.toHaveLength(0);
  expect(screen.getByText("r4")).toBeVisible();
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
        definition: populated.definition,
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
        definition: populated.definition,
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
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01");
});
