import { cleanup, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, expect, test, vi } from "vitest";
import type { CallConsoleController } from "@vxpipe/core";

const callConsole = vi.fn();
vi.mock("@vxpipe/react", () => ({
  CallConsole: (props: {
    header?: ReactNode;
    headerContext?: ReactNode;
    layout?: "contained" | "fill";
    maxHeight?: string;
  }) => {
    callConsole(props);
    return (
      <div data-layout={props.layout} data-testid="call-console">
        <div data-testid="console-header">{props.header}</div>
        <div data-testid="console-header-context">{props.headerContext}</div>
        Reusable call console
      </div>
    );
  },
}));

import { CallDetailsPage } from "./CallDetailsPage";
import { CallDetailsStory } from "./CallDetailsStory";

afterEach(() => {
  cleanup();
  callConsole.mockClear();
});

const context = {
  tenant: { key: "tn_demo_01", name: "Demo workspace" },
  definition: {
    id: "delivery-rescheduling",
    name: "Delivery rescheduling",
    latestRevision: 4,
    publishedRevision: 3,
  },
  callId: "call-1",
  definitionRevision: 3,
};

const controller = {
  details: {
    getSnapshot: vi.fn(),
    subscribe: vi.fn(() => () => undefined),
  },
} as unknown as CallConsoleController;

test("uses the existing header labels as return links without adding workspace tabs", () => {
  render(
    <CallDetailsPage
      state={{ status: "ready", ...context, controller, completeness: "complete" }}
      theme="light"
    />,
  );

  expect(screen.getByRole("heading", { name: "Call details" })).toHaveClass(
    "sr-only",
  );
  expect(screen.getByTestId("console-header")).toHaveTextContent("Vxpipe");
  expect(screen.getByTestId("console-header")).toHaveTextContent("Demo workspace");
  expect(screen.getByTestId("console-header")).toHaveTextContent("Delivery rescheduling");
  expect(screen.getByRole("navigation", { name: "Breadcrumb" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute("href", "/admin");
  expect(screen.getByRole("link", { name: "Demo workspace" })).toHaveAttribute("href", "/admin/tenants/tn_demo_01/definitions");
  expect(screen.getByRole("link", { name: "Delivery rescheduling" })).toHaveAttribute("href", "/admin/tenants/tn_demo_01/calls?definition_id=delivery-rescheduling");
  expect(screen.queryByRole("navigation", { name: "Tenant workspace" })).not.toBeInTheDocument();
  expect(screen.getByText("call-1")).toBeVisible();
  expect(screen.getByTestId("call-console")).toHaveTextContent(
    "v3 · call-1",
  );
  expect(screen.getByTestId("console-header")).not.toHaveTextContent("call-1");
  expect(screen.getByTestId("console-header-context")).toHaveTextContent(
    "v3 · call-1",
  );
  expect(
    screen.queryByRole("navigation", { name: "Primary navigation" }),
  ).not.toBeInTheDocument();
  expect(screen.getByTestId("call-console")).toBeVisible();
  expect(screen.getByTestId("call-console")).toHaveAttribute("data-layout", "fill");
  expect(callConsole).toHaveBeenCalledWith(
    expect.objectContaining({
      controller,
      headerContext: expect.anything(),
      theme: "light",
      header: expect.anything(),
      layout: "fill",
    }),
  );
  const props = callConsole.mock.calls[0]?.[0];
  expect(props.maxHeight).toBeUndefined();
});

test("keeps loading, unavailable, and malformed states distinct", () => {
  const view = render(
    <CallDetailsPage state={{ status: "loading", ...context }} />,
  );
  expect(screen.getByRole("main")).toHaveAttribute("aria-busy", "true");
  expect(screen.queryByTestId("call-console")).not.toBeInTheDocument();
  expect(screen.getByText("Vxpipe")).toBeVisible();
  expect(screen.getByText("Demo workspace")).toBeVisible();
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute("href", "/admin");

  view.rerender(
    <CallDetailsPage
      state={{ status: "unavailable", ...context, message: "Storage is unavailable." }}
    />,
  );
  expect(screen.getByRole("alert")).toHaveTextContent("Call unavailable");
  expect(screen.getByText("call-1")).toBeVisible();
  expect(screen.getByRole("link", { name: "Demo workspace" })).toBeVisible();

  view.rerender(
    <CallDetailsPage
      state={{ status: "malformed", ...context, message: "Invalid participants." }}
    />,
  );
  expect(screen.getByRole("alert")).toHaveTextContent("Call data could not be read");
  expect(screen.getByRole("alert")).toHaveTextContent("Invalid participants.");
});

test("warns when the inspection archive is partial", () => {
  render(
    <CallDetailsPage
      state={{ status: "ready", ...context, controller, completeness: "incomplete" }}
    />,
  );

  expect(screen.getByRole("status")).toHaveTextContent("Partial history");
});

test("the individual story return links load working admin previews", () => {
  render(<CallDetailsStory scenario="ongoing" theme="dark" />);
  expect(screen.getByText("Delivery rescheduling")).toBeVisible();
  for (const [name, path] of [
    ["Tenants", "/admin"],
    ["Demo workspace", "/admin/tenants/tn_demo_01/definitions"],
    ["Delivery rescheduling", "/admin/tenants/tn_demo_01/calls?definition_id=delivery-rescheduling"],
  ]) {
    const link = screen.getByRole("link", { name });
    const url = new URL(link.getAttribute("href")!, window.location.origin);
    expect(url.pathname).toBe("/iframe.html");
    expect(url.searchParams.get("id")).toBe("vxpipe-console-full-journey--review-flow");
    expect(url.hash).toBe(`#${path}`);
  }
});
