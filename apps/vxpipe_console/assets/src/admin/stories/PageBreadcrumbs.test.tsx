import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "../mcpStories/McpServicesStory";
import { CallSpecsPageStory, CallsPageStory } from "./ResourceStories";
import { CallDetailsStory } from "../CallDetailsStory";
import { ApiKeysStory } from "../apiKeys/ApiKeysStory";
import { AuthenticationStory } from "./AuthenticationStory";

vi.mock("@vxpipe/react", () => ({ CallConsole: ({ header }: { header: React.ReactNode }) => <div>{header}</div> }));
afterEach(() => { cleanup(); vi.restoreAllMocks(); window.history.replaceState({}, "", "/"); });

test("integration categories share one tenant breadcrumb", () => {
  render(<McpServicesStory scenario="picker" />);
  const breadcrumb = within(screen.getByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getByRole("link", { name: "Demo" })).toBeVisible();
  expect(breadcrumb.getByRole("link", { name: "Integrations" })).toBeVisible();
  expect(breadcrumb.getByText("AI models")).toHaveAttribute("aria-current", "page");
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "connected" } });
  expect(screen.getByRole("heading", { name: "Integrations", level: 1 })).toBeVisible();
});

test("directory search precedes the renamed other-MCP action", () => {
  render(<McpServicesStory scenario="picker" />);
  const search = screen.getByRole("searchbox", { name: "Search integrations" });
  const action = screen.getByRole("button", { name: "Connect other MCP" });
  expect(search.compareDocumentPosition(action) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  fireEvent.click(action);
  expect(screen.getByRole("dialog", { name: "Connect other MCP" })).toBeVisible();
});

test.each([["Call Specs", CallSpecsPageStory], ["Calls", CallsPageStory]] as const)("%s stories show a tenant-first breadcrumb with a working tenant link", (label, Story) => {
  vi.spyOn(window, "scrollTo").mockImplementation(() => undefined);
  render(<Story scenario="populated" theme="dark" />);
  const breadcrumb = within(screen.getByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getByText(label)).toHaveAttribute("aria-current", "page");
  fireEvent.click(breadcrumb.getByRole("link", { name: "Demo workspace" }));
  expect(screen.getByRole("heading", { name: "Dashboard", level: 1 })).toBeVisible();
});

test("call history begins with the tenant and offers a Calls breadcrumb", () => {
  render(<CallDetailsStory scenario="ended" theme="dark" />);
  const breadcrumb = within(screen.getByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getAllByRole("link")[0]).toHaveTextContent("Demo workspace");
  expect(breadcrumb.getByRole("link", { name: "Calls" })).toBeVisible();
  expect(breadcrumb.queryByText("Tenants")).not.toBeInTheDocument();
});

test("installation-wide API keys use Settings as their breadcrumb root", async () => {
  render(<ApiKeysStory initialCreating />);
  const breadcrumb = within(await screen.findByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getByText("Settings")).toBeVisible();
  fireEvent.click(await breadcrumb.findByRole("button", { name: "API Keys" }));
  expect(await screen.findByRole("table", { name: "API keys" })).toBeVisible();
});

test("role creation replaces its top back link with breadcrumbs and keeps Cancel in the form actions", () => {
  render(<AuthenticationStory actor="superadmin" initialPath="/roles/new" followLocation={false} theme="dark" />);
  const breadcrumb = within(screen.getByRole("navigation", { name: "Breadcrumb" }));
  expect(breadcrumb.getByRole("link", { name: "Roles" })).toBeVisible();
  expect(screen.queryByRole("link", { name: "Back to roles" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Cancel" })).toBeVisible();
});
