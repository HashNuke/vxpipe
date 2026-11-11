import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { NavigationShell } from "./NavigationShell";
import { navigationFixture } from "./navigationFixtures";
import { tenants } from "../authentication/fixtures";

afterEach(cleanup);
function Shell({ initialPath = `/t/${tenants[0].key}/calls` }: { initialPath?: string }) {
  const [path, setPath] = useState(initialPath);
  const { role, user } = navigationFixture("all");
  return <NavigationShell role={role} user={user} tenants={tenants} selected={tenants[0]} path={path} onNavigate={setPath} onLogout={vi.fn()} theme="dark" onRetry={vi.fn()}><main>{path}</main></NavigationShell>;
}

test("workspace exposes one Settings entry and settings replaces tenant navigation", () => {
  render(<Shell />);
  expect(screen.getByRole("combobox", { name: "Switch tenant" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Tenants" })).toHaveAttribute("href", "#/tenants");
  expect(screen.queryByRole("link", { name: "Users" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("link", { name: "Settings" }));
  expect(screen.queryByRole("combobox", { name: "Switch tenant" })).not.toBeInTheDocument();
  expect(screen.queryByRole("navigation", { name: "Tenant" })).not.toBeInTheDocument();
  const settings = screen.getByRole("navigation", { name: "Settings" });
  expect(within(settings).getAllByRole("link").map(link => link.textContent)).toEqual(["API Keys", "Roles", "Users", "Services", "Installation"]);
  fireEvent.click(within(settings).getByRole("link", { name: "Users" }));
  expect(within(settings).getByRole("link", { name: "Users" })).toHaveAttribute("aria-current", "page");
  fireEvent.click(screen.getByRole("link", { name: "Back to tenants" }));
  expect(screen.getByRole("main")).toHaveTextContent("/tenants");
});

test("direct settings URLs have a safe exit without tenant context", () => {
  render(<NavigationShell tenants={[]} path="/roles/example" projectedItems={{ tenant: [], platform: [{ label: "Roles", href: "/roles" }] }} onNavigate={vi.fn()} onLogout={vi.fn()} theme="dark" onRetry={vi.fn()} realLinks><main /></NavigationShell>);
  expect(screen.getByRole("link", { name: "Back to tenants" })).toHaveAttribute("href", "/tenants");
  expect(screen.getByRole("link", { name: "Roles" })).toHaveAttribute("aria-current", "page");
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
});

test("Settings is absent when the projection permits no platform pages", () => {
  render(<NavigationShell tenants={[]} path="/tenants" projectedItems={{ tenant: [], platform: [] }} onNavigate={vi.fn()} onLogout={vi.fn()} theme="dark" onRetry={vi.fn()}><main /></NavigationShell>);
  expect(screen.queryByRole("link", { name: "Settings" })).not.toBeInTheDocument();
});

test("the login redirect is not remembered as the exit from Settings", () => {
  const props = { tenants: [], projectedItems: { tenant: [], platform: [{ label: "Roles", href: "/roles" }] }, onNavigate: vi.fn(), onLogout: vi.fn(), theme: "dark" as const, onRetry: vi.fn(), realLinks: true };
  const view = render(<NavigationShell {...props} path="/"><main /></NavigationShell>);
  view.rerender(<NavigationShell {...props} path="/roles"><main /></NavigationShell>);
  expect(screen.getByRole("link", { name: "Back to tenants" })).toHaveAttribute("href", "/tenants");
});


test("personal settings share the settings sidebar and have distinct active links", () => {
  const { role, user } = navigationFixture("all");
  const view = render(<NavigationShell previewPersonalSettings role={role} user={user} tenants={[]} path="/account/connections" onNavigate={vi.fn()} onLogout={vi.fn()} theme="dark" onRetry={vi.fn()}><main /></NavigationShell>);
  expect(screen.getByRole("link", { name: "Users" })).toBeVisible();
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
  const personal = screen.getByRole("navigation", { name: "For you" });
  expect(within(personal).getByRole("link", { name: "Your connections" })).toHaveAttribute("aria-current", "page");
  expect(within(personal).getByRole("link", { name: "Your account" })).not.toHaveAttribute("aria-current");
  view.rerender(<NavigationShell previewPersonalSettings role={role} user={user} tenants={[]} path="/account" onNavigate={vi.fn()} onLogout={vi.fn()} theme="dark" onRetry={vi.fn()}><main /></NavigationShell>);
  expect(screen.getByRole("link", { name: "Your account" })).toHaveAttribute("aria-current", "page");
});

test("personal settings remain available without any platform permissions", () => {
  const props = { previewPersonalSettings: true, tenants: [], projectedItems: { tenant: [], platform: [] }, onNavigate: vi.fn(), onLogout: vi.fn(), theme: "dark" as const, onRetry: vi.fn() };
  const view = render(<NavigationShell {...props} path="/tenants"><main /></NavigationShell>);
  expect(screen.getByRole("link", { name: "Settings" })).toHaveAttribute("href", "#/account");
  expect(screen.queryByRole("link", { name: /account/i })).not.toBeInTheDocument();
  view.rerender(<NavigationShell {...props} path="/account/connections"><main /></NavigationShell>);
  expect(screen.getByRole("navigation", { name: "For you" })).toBeVisible();
  expect(screen.queryByRole("navigation", { name: "Settings" })).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Your account" })).toHaveAttribute("href", "#/account");
  expect(screen.getByRole("link", { name: "Your connections" })).toHaveAttribute("href", "#/account/connections");
});
