import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test("AI category page links survive browser history and remounts", () => {
  render(<McpServicesStory scenario="directory-paginated" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  expect(screen.getByText("4–6 of 11")).toBeVisible();
  const secondPage = window.location.hash;
  fireEvent.click(screen.getByRole("button", { name: "Previous page" }));
  window.history.replaceState({}, "", secondPage);
  fireEvent.popState(window);
  expect(screen.getByText("4–6 of 11")).toBeVisible();
  cleanup();
  render(<McpServicesStory scenario="directory-paginated" />);
  expect(screen.getByText("4–6 of 11")).toBeVisible();
  expect(window.location.hash).toBe(secondPage);
});

test("remote results paginate and resolve connected status on later pages", () => {
  render(<McpServicesStory scenario="directory-paginated" />);
  const pages = within(screen.getByRole("navigation", { name: "Integration pages" }));
  expect(pages.getByText("1–3 of 6")).toBeVisible();
  expect(pages.getByRole("button", { name: "Previous page" })).toBeDisabled();
  expect(screen.queryByRole("button", { name: "Edit Cal.com" })).not.toBeInTheDocument();
  fireEvent.click(pages.getByRole("button", { name: "Next page" }));
  expect(pages.getByText("4–6 of 6")).toBeVisible();
  expect(pages.getByRole("button", { name: "Next page" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
  expect(window.location.hash).toContain("?cursor=");
  const secondPage = window.location.hash;
  fireEvent.click(pages.getByRole("button", { name: "Previous page" }));
  expect(screen.queryByRole("button", { name: "Edit Cal.com" })).not.toBeInTheDocument();
  window.history.replaceState({}, "", secondPage);
  fireEvent.popState(window);
  expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
});

test("search spans unloaded pages and resets the cursor, as does category navigation", () => {
  render(<McpServicesStory scenario="directory-paginated" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Google" } });
  expect(screen.getByRole("button", { name: "Connect Google Calendar" })).toBeVisible();
  expect(screen.getByText("1–3 of 4")).toBeVisible();
  expect(window.location.hash).toContain("q=Google");
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "" } });
  fireEvent.click(screen.getByRole("button", { name: "Next page" }));
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "office" } });
  expect(window.location.hash).not.toContain("cursor=");
  expect(screen.getByText("1–2 of 2")).toBeVisible();
});

test("a failed next page retains the current rows and retries that page", () => {
  render(<McpServicesStory scenario="directory-page-error" />);
  expect(screen.getByRole("alert")).toHaveTextContent("Could not load the next page");
  expect(screen.getByRole("button", { name: "Connect Acme appointments" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry page" }));
  expect(screen.getByRole("button", { name: "Edit Cal.com" })).toBeVisible();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});

test("loading another page keeps current rows and prevents repeated page requests", () => {
  render(<McpServicesStory scenario="directory-page-loading" />);
  expect(screen.getByRole("status")).toHaveTextContent("Loading next page");
  expect(screen.getByRole("button", { name: "Connect Acme appointments" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Next page" })).toBeDisabled();
});

test("an expired page link can restart at the first page without losing the category", () => {
  window.history.replaceState({}, "", "#/t/demo_mcp_preview/services/calendar?cursor=expired");
  render(<McpServicesStory scenario="directory-paginated" />);
  expect(screen.getByRole("alert")).toHaveTextContent("This page has expired");
  fireEvent.click(screen.getByRole("button", { name: "Start from first page" }));
  expect(screen.getByText("1–3 of 6")).toBeVisible();
  expect(window.location.hash).toBe("#/t/demo_mcp_preview/services/calendar");
});
