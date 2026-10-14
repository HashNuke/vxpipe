import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { NavigationJourney } from "./NavigationJourney";
vi.mock("@vxpipe/react", () => ({ CallConsole: () => <div>Call inspector</div> }));
vi.mock("../callSpecEditor/flow-canvas", () => ({ FlowCanvas: () => <div>Editor canvas</div> }));
beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });
test("single-tenant entry shows dashboard with only permitted links", () => {
  render(<NavigationJourney persona="single" />);
  expect(screen.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  expect(screen.queryByRole("navigation", { name: "Platform" })).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "My account" })).toBeVisible();
  expect(screen.queryByText("acme_demo_000001")).not.toBeInTheDocument();
});
test("multi-tenant directory and search show only allowed tenants, selection opens dashboard", async () => {
  render(<NavigationJourney persona="multiple" />);
  expect(screen.getByRole("heading", { name: "My tenants" })).toBeVisible();
  expect(screen.queryByText("Contoso Support")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("combobox", { name: "Switch tenant" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Search tenants" }), { target: { value: "Northwind" } });
  fireEvent.click(await screen.findByRole("option", { name: /Northwind/ }));
  expect(screen.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Northwind dashboard" })).toHaveAttribute("href", "#/t/northwind_000001/dashboard");
});
test("platform and tenant services have distinct titles and correct active groups", () => {
  render(<NavigationJourney initialPath="/platform/services" />);
  expect(screen.getByRole("heading", { name: "Platform Services" })).toBeVisible();
  const platform = screen.getByRole("navigation", { name: "Platform" });
  expect(within(platform).getByRole("link", { name: "Services" })).toHaveAttribute("aria-current", "page");
});
test("logout removes the private navigation and shows login", () => {
  render(<NavigationJourney />);
  fireEvent.click(screen.getByRole("button", { name: "Logout" }));
  expect(screen.queryByRole("combobox", { name: "Switch tenant" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Sign in to Vxpipe" })).toBeVisible();
});

test("direct platform and API key URLs do not bypass the member presentation policy", () => {
  const view = render(<NavigationJourney persona="member" initialPath="/platform/services" />);
  expect(screen.getByRole("heading", { name: "Access unavailable" })).toBeVisible();
  view.unmount();
  render(<NavigationJourney persona="member" initialPath="/t/acme_demo_000001/api-keys" />);
  expect(screen.getByRole("heading", { name: "Access unavailable" })).toBeVisible();
});
test("legacy service content keeps the sidebar as its only workspace navigation", () => {
  render(<NavigationJourney initialPath="/t/acme_demo_000001/legacy-services" />);
  expect(screen.getByRole("heading", { name: "Services" })).toBeVisible();
  expect(screen.queryByRole("navigation", { name: "Tenant workspace" })).not.toBeInTheDocument();
  expect(screen.getAllByRole("link", { name: "Vxpipe" })).toHaveLength(1);
});
test("call inspector and editor remain outside the navigation shell", () => {
  const view = render(<NavigationJourney initialPath="/t/acme_demo_000001/calls/example" />);
  expect(screen.queryByRole("complementary", { name: "Console navigation" })).not.toBeInTheDocument();
  view.unmount();
  render(<NavigationJourney initialPath="/t/acme_demo_000001/editor" />);
  expect(screen.queryByRole("complementary", { name: "Console navigation" })).not.toBeInTheDocument();
});
test("tenant creation is retained for an authorized platform operator", () => {
  render(<NavigationJourney initialPath="/tenants" />);
  fireEvent.click(screen.getByRole("link", { name: "New tenant" }));
  expect(screen.getByRole("heading", { name: "New tenant" })).toBeVisible();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});
test("platform read access hides credential mutation controls", () => {
  render(<NavigationJourney persona="platform-reader" initialPath="/platform/services" />);
  expect(screen.getByRole("heading", { name: "Platform Services" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
});
test("tenant service read access includes the API-key destination without mutations", () => {
  render(<NavigationJourney persona="service-reader" initialPath="/t/acme_demo_000001/services" />);
  expect(screen.getByRole("heading", { name: "Services" })).toBeVisible();
  expect(screen.getByRole("button", { name: "API keys" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
});
test("read-only member cannot mutate samples or invoke platform setup", () => {
  const view = render(<NavigationJourney persona="member" initialPath="/t/acme_demo_000001/samples" />);
  expect(screen.getByRole("heading", { name: "Access unavailable" })).toBeVisible();
  view.unmount();
  render(<NavigationJourney persona="none" initialPath="/getting-started" />);
  expect(screen.getByRole("heading", { name: "Access unavailable" })).toBeVisible();
});
test("workspace API keys remain available before voice readiness", () => {
  render(<NavigationJourney initialPath="/t/acme_demo_000001/services" />);
  expect(screen.queryByRole("button", { name: "Continue" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "API keys" }));
  expect(screen.getByRole("heading", { name: "Create API Keys" })).toBeVisible();
});
test("legacy service read permission includes masked credential metadata", () => {
  render(<NavigationJourney persona="service-reader" initialPath="/t/acme_demo_000001/legacy-services" />);
  expect(screen.getByText("Credentials")).toBeVisible();
  expect(screen.getAllByText(/\*{4}/).length).toBeGreaterThan(0);
});

test("tenant selection needs no review hint", () => {
  render(<NavigationJourney initialPath="/" />);
  expect(screen.queryByText("Select a tenant to open its workspace.")).not.toBeInTheDocument();
});

test("directory rows show dates without tenant keys or Setup links, even for administrators", () => {
  render(<NavigationJourney initialPath="/tenants" />);
  expect(screen.queryByText("acme_demo_000001")).not.toBeInTheDocument();
  expect(screen.getAllByText(/^Created /).length).toBeGreaterThan(0);
  expect(screen.queryByRole("link", { name: /^Setup / })).not.toBeInTheDocument();
});
test("directory and dashboard use skeleton loading states", () => {
  const view = render(<NavigationJourney initialPath="/tenants" state="loading" />);
  expect(screen.getByRole("status", { name: "Loading tenants" })).toBeVisible();
  view.unmount();
  render(<NavigationJourney persona="single" state="loading" />);
  expect(screen.getByRole("status", { name: "Loading dashboard" })).toBeVisible();
});
test("dashboard has no duplicate resource buttons or retry action", () => {
  render(<NavigationJourney persona="single" state="unavailable" />);
  expect(screen.queryByRole("button", { name: "Try again" })).not.toBeInTheDocument();
  expect(screen.getAllByRole("link", { name: "Calls" })).toHaveLength(1);
});
