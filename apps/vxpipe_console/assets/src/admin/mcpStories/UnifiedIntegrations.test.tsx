import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";
import { SetupStory } from "../stories/SetupStory";
import { NavigationJourney } from "../navigation/NavigationJourney";
import { NavigationServices } from "../navigation/NavigationServices";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test("tenant Integrations opens connected rows and categories have their own URLs and breadcrumbs", () => {
  render(<McpServicesStory />);
  expect(screen.getByRole("heading", { name: "Integrations", level: 1 })).toBeVisible();
  const categories = within(screen.getByRole("navigation", { name: "Integration categories" }));
  expect(categories.getAllByRole("link")[0]).toHaveTextContent("Connected integrations");
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/connected");
  for (const name of ["AI services", "Telephony", "MCPs"]) expect(screen.getByRole("region", { name })).toBeVisible();
  expect(screen.getByRole("button", { name: "Manage Cal.com" })).toBeVisible();
  expect(screen.getByRole("article", { name: "Deepgram" })).toHaveClass("service-directory-row");
  expect(screen.getByRole("heading", { name: "Integrations", level: 1 })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("searchbox", { name: "Search integrations" }), { target: { value: "Cal.com" } });
  expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
  expect(screen.queryByRole("article", { name: "Deepgram" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "" } });
  const ai = categories.getByRole("link", { name: /^AI models/ });
  expect(ai).toHaveAttribute("href", "#/t/demo_mcp_preview/services/ai");
  fireEvent.click(ai);
  expect(screen.getByRole("button", { name: "Connect OpenAI" })).toBeVisible();
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/ai");
  expect(within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText("AI models")).toHaveAttribute("aria-current", "page");
  window.history.replaceState({}, "", "#/t/demo_mcp_preview/services/connected");
  fireEvent.popState(window);
  expect(screen.getByRole("button", { name: "Manage Cal.com" })).toBeVisible();
});

test("platform Integrations has connected, AI and telephony categories only", () => {
  render(<SetupStory scenario="platform-configured" theme="dark" />);
  expect(screen.getByRole("heading", { name: "Platform Integrations", level: 1 })).toBeVisible();
  expect(within(screen.getByRole("navigation", { name: "Settings" })).getByRole("link", { name: "Platform Integrations" })).toBeVisible();
  const categories = within(screen.getByRole("navigation", { name: "Integration categories" }));
  expect(categories.getAllByRole("link")).toHaveLength(3);
  expect(window.location.hash).toBe("#/platform/services/connected");
  expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "connected" } });
  expect(screen.getByRole("region", { name: "AI services" })).toBeVisible();
  expect(screen.getByRole("region", { name: "Telephony" })).toBeVisible();
  expect(screen.queryByRole("region", { name: "MCPs" })).not.toBeInTheDocument();
});

test("connecting an inherited provider from the directory creates a tenant override", () => {
  render(<NavigationServices tenant={{ key: "demo", name: "Demo" }} canManagePlatform onNavigate={vi.fn()} />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.click(screen.getByRole("button", { name: "Edit Google AI Studio" }));
  fireEvent.click(screen.getByRole("button", { name: "Override for this tenant" }));
  expect(screen.getByRole("dialog", { name: "Override Google AI Studio" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("API key", { exact: true }), { target: { value: "storybook-example-key" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(screen.getByRole("button", { name: "Manage Google AI Studio" })).toBeVisible();
  expect(within(screen.getByRole("article", { name: "Google AI Studio" })).queryByText("Inherited from platform")).not.toBeInTheDocument();
});

test("a category URL opens directly and platform rejects tenant-only categories", () => {
  window.history.replaceState({}, "", "#/t/demo_mcp_preview/services/calendar");
  const view = render(<McpServicesStory />);
  expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
  view.unmount();
  window.history.replaceState({}, "", "#/platform/services/calendar");
  render(<SetupStory scenario="platform-configured" theme="dark" />);
  expect(window.location.hash).toBe("#/platform/services/connected");
  expect(screen.queryByRole("button", { name: "Edit Cal.com" })).not.toBeInTheDocument();
});


test("the main Integrations link returns to connected integrations", () => {
  vi.spyOn(window, "scrollTo").mockImplementation(() => undefined);
  render(<NavigationJourney initialPath="/platform/services" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  expect(window.location.hash).toBe("#/platform/services/ai");
  fireEvent.click(within(screen.getByRole("navigation", { name: "Settings" })).getByRole("link", { name: "Platform Integrations" }));
  expect(screen.getByLabelText("Category")).toHaveValue("connected");
  expect(window.location.hash).toBe("#/platform/services/connected");
});
