import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test("search from any category returns MCP, AI and telephony integrations globally", () => {
  render(<McpServicesStory scenario="directory-calendar" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Google" } });
  expect(screen.getByRole("button", { name: "Connect Google AI Studio" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Google Calendar" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Google Sheets" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Google Docs" })).toBeVisible();
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/search?q=Google");
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Telnyx" } });
  expect(screen.getByRole("button", { name: "Edit Telnyx" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "office" } });
  expect(screen.getByRole("searchbox")).toHaveValue("");
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/office");
});

test("a future native provider is filtered out for this installation version", () => {
  render(<McpServicesStory scenario="directory-search-versions" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Example" } });
  expect(screen.getByRole("button", { name: "Connect Example knowledge" })).toBeVisible();
  expect(screen.queryByText("Example future AI")).not.toBeInTheDocument();
  expect(screen.getByText("1–1 of 1")).toBeVisible();
});
