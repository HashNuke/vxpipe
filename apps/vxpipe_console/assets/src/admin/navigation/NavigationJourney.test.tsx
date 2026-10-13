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
  fireEvent.click(screen.getByRole("button", { name: "New tenant" }));
  expect(screen.getByRole("dialog", { name: "New tenant" })).toBeVisible();
});
test("API-key-only Services does not expose provider inventory or write controls", () => {
  render(<NavigationJourney persona="keys-only" initialPath="/t/acme_demo_000001/services" />);
  expect(screen.getByRole("heading", { name: "Services" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "API keys" })).toBeVisible();
  expect(screen.queryByText("Deepgram")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Create API key" })).not.toBeInTheDocument();
});
test("platform read access hides credential mutation controls", () => {
  render(<NavigationJourney persona="platform-reader" initialPath="/platform/services" />);
  expect(screen.getByRole("heading", { name: "Platform Services" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
});
test("tenant service read access does not disclose an API-key destination", () => {
  render(<NavigationJourney persona="service-reader" initialPath="/t/acme_demo_000001/services" />);
  expect(screen.getByRole("heading", { name: "Services" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "API keys" })).not.toBeInTheDocument();
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
test("legacy service read permission does not disclose credential metadata", () => {
  render(<NavigationJourney persona="service-reader" initialPath="/t/acme_demo_000001/legacy-services" />);
  expect(screen.queryByText("Credentials")).not.toBeInTheDocument();
  expect(screen.queryByText(/\*{4}/)).not.toBeInTheDocument();
});
