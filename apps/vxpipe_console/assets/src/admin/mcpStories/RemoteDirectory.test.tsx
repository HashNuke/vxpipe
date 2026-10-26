import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test("local directory rows show their saved status and edit inherited credentials", () => {
  render(<McpServicesStory scenario="directory-ai" />);
  const row = screen.getByRole("article", { name: "Deepgram" });
  expect(within(row).getByText("Connected")).toBeInTheDocument();
  expect(within(row).queryByText("Inherited from platform")).not.toBeInTheDocument();
  expect(within(row).queryByRole("button", { name: /Connect/ })).not.toBeInTheDocument();
  fireEvent.click(within(row).getByRole("button", { name: "Edit Deepgram" }));
  expect(screen.getByRole("dialog")).toHaveTextContent("This tenant uses the platform service");
  expect(screen.getByRole("button", { name: /Override/ })).toBeVisible();
});

test("MCP directory status comes from tenant records and Edit opens the saved connection", () => {
  render(<McpServicesStory scenario="directory-calendar" />);
  const row = screen.getByRole("article", { name: "Cal.com" });
  expect(within(row).getByText("Connected")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Connect Calendly" })).toBeVisible();
  fireEvent.click(within(row).getByRole("button", { name: "Edit Cal.com" }));
  const dialog = screen.getByRole("dialog", { name: "Cal.com" });
  fireEvent.click(within(dialog).getByRole("button", { name: "Disconnect" }));
  fireEvent.click(screen.getByRole("button", { name: "Disconnect MCP" }));
  expect(screen.getByRole("button", { name: "Connect Cal.com" })).toBeVisible();
});

test("a category supplied by the remote directory has its own URL and breadcrumb", () => {
  render(<McpServicesStory scenario="directory-expanded" />);
  fireEvent.click(within(screen.getByRole("navigation", { name: "Integration categories" })).getByRole("link", { name: /Knowledge base/ }));
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/knowledge");
  expect(within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText("Knowledge base")).toHaveAttribute("aria-current", "page");
  fireEvent.click(screen.getByRole("button", { name: "Connect Example knowledge" }));
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
  expect(screen.getByRole("dialog", { name: "Connect Example knowledge" })).toBeVisible();
});

test("a remote outage preserves local categories and existing MCP management", () => {
  render(<McpServicesStory scenario="directory-unavailable" />);
  expect(screen.getByText("Integration directory unavailable")).toBeVisible();
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "connected" } });
  expect(screen.getByRole("button", { name: "Manage Cal.com" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  expect(screen.getByRole("button", { name: "Edit Deepgram" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry directory" }));
  expect(within(screen.getByRole("navigation", { name: "Integration categories" })).getByRole("link", { name: /Calendar/ })).toBeVisible();
});

test.each(["directory-connections-loading", "directory-connections-error"] as const)("%s never presents an unknown connection as available to connect", scenario => {
  render(<McpServicesStory scenario={scenario} />);
  expect(screen.queryByRole("button", { name: "Connect Cal.com" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Edit Cal.com" })).not.toBeInTheDocument();
  expect(screen.queryByText("Connected", { exact: true })).not.toBeInTheDocument();
  if (scenario.endsWith("error")) {
    fireEvent.click(screen.getByRole("button", { name: "Retry connections" }));
    expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
  }
});

test("expired authorization is editable but never marked connected", () => {
  render(<McpServicesStory scenario="directory-reconnect" />);
  const row = screen.getByRole("article", { name: "Cal.com" });
  expect(within(row).getByText("Reconnect required")).toBeVisible();
  expect(within(row).queryByText("Connected")).not.toBeInTheDocument();
  fireEvent.click(within(row).getByRole("button", { name: "Edit Cal.com" }));
  expect(screen.getByRole("dialog", { name: "Cal.com" })).toBeVisible();
});
