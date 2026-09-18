import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { CallSpecCallsPage } from "./CallSpecCallsPage";
import { CallSpecCallsStory } from "./CallSpecCallsStory";
import type { CallSpecCallsPageState } from "./callTypes";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

const populated: CallSpecCallsPageState = {
  status: "ready",
  tenant: { key: "tn_demo_01", name: "Demo workspace" },
  callSpecs: [
    { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    { id: "appointment-reminders", name: "Appointment reminders" },
  ],
  selectedCallSpecId: null,
  calls: [
    {
      id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
      callSpecId: "delivery-rescheduling",
      callSpecName: "Delivery rescheduling",
      callSpecRevision: 3,
      state: "ongoing",
      createdAt: "2026-09-17T02:20:00.000Z",
    },
    {
      id: "018f27a2-51d5-77c9-a44f-e5c648bf8495",
      callSpecId: "delivery-rescheduling",
      callSpecName: "Delivery rescheduling",
      callSpecRevision: 2,
      state: "ended",
      createdAt: "2026-09-16T08:00:00.000Z",
    },
    {
      id: "018f2791-f803-781c-9e96-35cc46d612cc",
      callSpecId: "delivery-rescheduling",
      callSpecName: "Delivery rescheduling",
      callSpecRevision: 4,
      state: "ended",
      createdAt: "2026-09-16T06:10:00.000Z",
    },
  ],
  pagination: {
    label: "1–3 of 3",
    hasPrevious: false,
    hasNext: true,
  },
};

test("shows tenant navigation and opens call links in separate tabs", () => {
  render(<CallSpecCallsPage state={populated} />);

  expect(screen.getByRole("heading", { name: "Calls" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute(
    "href",
    "/admin",
  );
  expect(screen.getByRole("link", { name: "Demo workspace" })).toHaveAttribute(
    "href",
    "/admin/tenants/tn_demo_01",
  );
  expect(
    screen.getByRole("link", { name: "Call specs" }),
  ).toHaveAttribute("href", "/admin/tenants/tn_demo_01/call-specs");
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
  expect(call).toHaveAttribute("target", "_blank");
  expect(call).toHaveAttribute("rel", "noopener noreferrer");
  expect(call).toHaveAccessibleName(/opens in a new tab/i);
});

test("searches, selects, and resets a call spec filter through injected actions", async () => {
  const selectCallSpec = vi.fn();

  const view = render(
    <CallSpecCallsPage
      onSelectCallSpec={selectCallSpec}
      state={populated}
    />,
  );

  fireEvent.click(screen.getByRole("combobox", { name: "Call spec" }));
  const search = within(await screen.findByRole("dialog")).getByPlaceholderText(
    "Search call specs…",
  );
  expect(search).toHaveAttribute("aria-label", "Search call specs");
  fireEvent.change(search, {
    target: { value: "appointment" },
  });
  expect(
    screen.getByRole("option", { name: "Appointment reminders" }),
  ).toBeVisible();
  expect(
    screen.queryByRole("option", { name: "Delivery rescheduling" }),
  ).not.toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("option", { name: "Appointment reminders" }),
  );
  expect(selectCallSpec).toHaveBeenCalledWith("appointment-reminders");

  view.rerender(
    <CallSpecCallsPage
      onSelectCallSpec={selectCallSpec}
      state={{ ...populated, selectedCallSpecId: "delivery-rescheduling" }}
    />,
  );
  fireEvent.click(screen.getByRole("button", { name: "Show all calls" }));
  expect(selectCallSpec).toHaveBeenLastCalledWith(null);
});

test("discloses when the call spec filter contains only the bounded first page", () => {
  render(
    <CallSpecCallsPage
      state={{ ...populated, callSpecsTruncated: true }}
    />,
  );

  expect(screen.getByText(/first 100 call specs/i)).toBeVisible();
  expect(screen.getByRole("link", { name: "Call specs" })).toBeVisible();
});

test("keeps valid empty filters distinct from unknown filters", () => {
  const { rerender } = render(
    <CallSpecCallsPage
      state={{
        ...populated,
        selectedCallSpecId: "appointment-reminders",
        calls: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByText("No matching calls")).toBeVisible();

  rerender(
    <CallSpecCallsPage
      state={{
        ...populated,
        selectedCallSpecId: "missing-call-spec",
        calls: [],
        pagination: null,
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent(
    "This call spec is not available",
  );
});

test("shows the compact call directory columns and only public lifecycle states", () => {
  render(<CallSpecCallsPage state={populated} />);

  expect(screen.getByText("ID")).toBeVisible();
  expect(screen.getAllByText("Call spec")).toHaveLength(2);
  expect(screen.getByText("State")).toBeVisible();
  expect(screen.getByText("Time")).toBeVisible();
  expect(screen.getByText("Ongoing")).toBeVisible();
  expect(screen.getAllByText("Ended")).toHaveLength(2);
  expect(screen.queryByText("Archive")).not.toBeInTheDocument();
  expect(screen.queryByText("Duration")).not.toBeInTheDocument();
  expect(screen.getByText("Version 4")).toBeVisible();
});

test("shows local call time with relative time underneath", () => {
  const createdAt = "2026-09-15T09:30:00.000Z";
  const { container } = render(
    <CallSpecCallsPage
      state={{
        ...populated,
        calls: [
          {
            id: "018f2708-76d2-72f5-885c-d2d62a8a8ea1",
            callSpecId: "delivery-rescheduling",
            callSpecName: "Delivery rescheduling",
            callSpecRevision: 1,
            state: "ongoing",
            createdAt,
          },
        ],
      }}
    />,
  );

  const time = container.querySelector(`time[datetime="${createdAt}"]`);
  expect(time).not.toBeNull();
  expect(time).toHaveTextContent(/ago/);
  expect(time).toHaveAttribute("title");
});

test("keeps empty and unavailable call results distinct", () => {
  const { rerender } = render(
    <CallSpecCallsPage
      state={{ ...populated, calls: [], pagination: null }}
    />,
  );

  expect(screen.getByText("No calls yet")).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();

  rerender(
    <CallSpecCallsPage
      state={{
        status: "unavailable",
        tenant: populated.tenant,
        callSpecs: populated.callSpecs,
        selectedCallSpecId: null,
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
    <CallSpecCallsPage
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
    <CallSpecCallsPage
      state={{
        status: "loading",
        tenant: populated.tenant,
        callSpecs: populated.callSpecs,
        selectedCallSpecId: null,
      }}
    />,
  );

  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(
    screen.queryByRole("link", { name: /^open call/i }),
  ).not.toBeInTheDocument();
});

test("the paginated call story reaches its advertised final page", () => {
  render(<CallSpecCallsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));

  expect(screen.getByText("9–12 of 12")).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("the populated story includes working pagination", () => {
  render(<CallSpecCallsStory scenario="populated" theme="dark" />);

  expect(screen.getByText("1–9 of 27")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  expect(screen.getByText("10–18 of 27")).toBeVisible();
});

test("pagination preserves each call's recorded time", () => {
  render(<CallSpecCallsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  const rows = screen.getAllByRole("link", { name: /^open call/i });

  expect(rows).toHaveLength(4);
  expect(rows.every((row) => row.querySelector("time"))).toBe(true);
});

test("call story links to a standalone journey tab while preserving the directory", () => {
  window.history.replaceState(
    {},
    "",
    "/iframe.html?id=vxpipe-console-calls--populated",
  );
  render(<CallSpecCallsStory scenario="populated" theme="dark" />);

  const call = screen.getByRole("link", { name: /open call 018f27cb/i });
  expect(call).toHaveAttribute("target", "_blank");
  const destination = new URL(
    call.getAttribute("href")!,
    window.location.origin,
  );
  expect(destination.pathname).toBe("/iframe.html");
  expect(destination.searchParams.get("id")).toBe(
    "vxpipe-console-full-journey--review-flow",
  );
  expect(destination.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls/018f27cb-6f87-7d1c-a61f-8873cb667342",
  );
  fireEvent.click(call);
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe("");

  fireEvent.click(screen.getByRole("link", { name: "Demo workspace" }));
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01/call-specs");
});

test("call story keeps the selected call spec in its URL and visible results", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-calls--populated");
  render(<CallSpecCallsStory scenario="populated" theme="dark" />);

  fireEvent.click(screen.getByRole("combobox", { name: "Call spec" }));
  fireEvent.click(
    screen.getByRole("option", { name: "Appointment reminders" }),
  );

  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/calls?call_spec_id=appointment-reminders",
  );
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(2);
});

test("call story clears stale pagination when its call spec filter changes", () => {
  render(<CallSpecCallsStory scenario="paginated" theme="dark" />);

  fireEvent.click(screen.getByRole("combobox", { name: "Call spec" }));
  fireEvent.click(
    screen.getByRole("option", { name: "Appointment reminders" }),
  );

  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(2);
  expect(
    screen.queryByRole("button", { name: "Next page" }),
  ).not.toBeInTheDocument();

  fireEvent.click(screen.getByRole("button", { name: "Show all calls" }));
  expect(screen.getAllByRole("link", { name: /^open call/i })).toHaveLength(9);
  expect(
    screen.queryByRole("button", { name: "Next page" }),
  ).not.toBeInTheDocument();
});
