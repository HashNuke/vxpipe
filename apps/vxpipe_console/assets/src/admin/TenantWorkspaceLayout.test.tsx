import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import type { ComponentProps } from "react";
import { afterEach, expect, test, vi } from "vitest";

import { callFixture } from "./callFixtures";
import { CallSpecCallsPage } from "./CallSpecCallsPage";
import { callSpecFixture } from "./callSpecFixtures";
import { serviceFixture } from "./serviceFixtures";
import { TenantCallSpecsPage } from "./TenantCallSpecsPage";
import { TenantServicesPage } from "./TenantServicesPage";

afterEach(cleanup);

type SharedProps = Pick<ComponentProps<typeof TenantServicesPage>, "headerActions" | "onSelectTenants">;

test.each([
  {
    title: "Call specs",
    renderPage: (props: SharedProps) => <TenantCallSpecsPage {...props} state={callSpecFixture("populated")} />,
  },
  {
    title: "Calls",
    renderPage: (props: SharedProps) => <CallSpecCallsPage {...props} state={callFixture("populated")} />,
  },
  {
    title: "Services",
    renderPage: (props: SharedProps) => <TenantServicesPage {...props} state={serviceFixture("populated")} />,
  },
])("$title keeps tenant context in the app header and identifies the page once visually", ({ title, renderPage }) => {
  const selectTenants = vi.fn();
  render(renderPage({
    headerActions: <button type="button">Sign out</button>,
    onSelectTenants: selectTenants,
  }));

  const header = within(screen.getByText("Vxpipe").closest("header")!);
  const breadcrumb = within(header.getByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getByText("Demo workspace")).toBeVisible();
  expect(breadcrumb.queryByText(title)).not.toBeInTheDocument();
  expect(header.queryByText("Admin")).not.toBeInTheDocument();
  expect(header.getByRole("button", { name: "Sign out" })).toBeVisible();
  expect(screen.getByRole("heading", { name: title, level: 1 })).toHaveClass("sr-only");
  expect(within(screen.getByRole("navigation", { name: "Tenant workspace" })).getByRole("link", { name: title })).toHaveAttribute("aria-current", "page");

  fireEvent.click(breadcrumb.getByRole("link", { name: "Tenants" }));
  expect(selectTenants).toHaveBeenCalledOnce();
});

test("credential setup makes the relocated tenant navigation and account actions inert", () => {
  render(<TenantServicesPage headerActions={<button type="button">Sign out</button>} state={serviceFixture("populated")} />);
  const header = screen.getByText("Vxpipe").closest("header")!;
  const trigger = screen.getByRole("button", { name: "Connect a service" });

  fireEvent.click(trigger);

  expect(header).toHaveAttribute("inert");
  expect(screen.queryByRole("navigation", { name: "Breadcrumb" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Sign out" })).not.toBeInTheDocument();
  expect(screen.getByRole("dialog", { name: "Connect a service" })).toBeVisible();

  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });

  expect(header).not.toHaveAttribute("inert");
  expect(screen.getByRole("navigation", { name: "Breadcrumb" })).toBeVisible();
  expect(trigger).toHaveFocus();
});
