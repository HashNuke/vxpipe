import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); vi.useRealTimers(); window.history.replaceState({}, "", "/"); });

test.each(["connected", "directory-ai", "directory-unavailable", "directory-expanded"] as const)("%s protects inherited services without platform write access", scenario => {
  render(<McpServicesStory scenario={scenario} canManagePlatform={false} />);
  if (scenario === "directory-expanded") fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Deepgram" } });
  const row = within(screen.getByRole("article", { name: "Deepgram" }));
  expect(row.queryByText("Inherited from platform")).not.toBeInTheDocument();
  if (scenario === "connected") {
    expect(row.queryByRole("button", { name: "Manage Deepgram" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Manage Telnyx" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Manage Cal.com" })).toBeEnabled();
  } else {
    expect(row.getByRole("button", { name: "Edit Deepgram" })).toBeDisabled();
    fireEvent.click(row.getByRole("button", { name: "Edit Deepgram" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  }
});

test("platform writers can still manage an inherited integration", () => {
  render(<McpServicesStory scenario="connected" canManagePlatform />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  expect(screen.getByRole("dialog", { name: "Manage Deepgram" })).toBeVisible();
});

test("the directory loading preview resolves to the requested category", () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="directory-loading" />);
  expect(screen.getByRole("status", { name: "Loading integration directory" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Connect Calendly" })).not.toBeInTheDocument();
  act(() => vi.advanceTimersByTime(1500));
  expect(screen.queryByRole("status", { name: "Loading integration directory" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Connect Calendly" })).toBeEnabled();
});

test("local inventory and built-in categories do not wait for the directory", () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="directory-loading" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "connected" } });
  expect(screen.queryByRole("status", { name: "Loading integration directory" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Manage Cal.com" })).toBeEnabled();
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  expect(screen.queryByRole("status", { name: "Loading integration directory" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Connect OpenAI" })).toBeEnabled();
  act(() => vi.advanceTimersByTime(1500));
  expect(screen.getByLabelText("Category")).toHaveValue("ai");
});
