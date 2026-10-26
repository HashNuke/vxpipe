import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); vi.useRealTimers(); window.history.replaceState({}, "", "/"); });

test("manage opens authentication with account context and direct reconnect", () => {
  render(<McpServicesStory scenario="connected" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Cal.com" }));
  const dialog = within(screen.getByRole("dialog", { name: "Cal.com" }));
  expect(dialog.getByText("reception@example.test")).toBeVisible();
  expect(dialog.getByRole("button", { name: /Authentication:.*CIMD/ })).toBeVisible();
  expect(dialog.getByRole("tab", { name: "Authentication" })).toHaveAttribute("aria-selected", "true");
  expect(dialog.getByRole("tab", { name: "Authentication" })).toHaveFocus();
  expect(dialog.queryByText("Available to")).not.toBeInTheDocument();
  expect(dialog.queryByRole("button", { name: "Edit connection" })).not.toBeInTheDocument();
  const authentication = within(dialog.getByRole("tabpanel", { name: "Authentication" }));
  fireEvent.click(authentication.getByRole("button", { name: "Reconnect" }));
  expect(screen.getByRole("button", { name: "Simulate authorization" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Cancel authorization" }));
  expect(screen.getByRole("dialog", { name: "Cal.com" })).toBeVisible();
});

test("tools have a separate searchable tab with refresh and no setup commentary", () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="connected" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Cal.com" }));
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Tools" }), { button: 0, ctrlKey: false });
  const panel = within(screen.getByRole("tabpanel", { name: "Tools" }));
  expect(panel.getByRole("heading", { name: "Available tools (4)" })).toBeVisible();
  expect(panel.getByRole("list", { name: "Available tools" })).toBeVisible();
  expect(panel.queryByText("Preview data")).not.toBeInTheDocument();
  expect(panel.queryByText("Refreshing this list never enables new tools for an agent.")).not.toBeInTheDocument();
  fireEvent.change(panel.getByRole("searchbox", { name: "Search tools" }), { target: { value: "slots" } });
  expect(panel.getByText("get_slots")).toBeVisible();
  expect(panel.queryByText("create_booking")).not.toBeInTheDocument();
  const refresh = panel.getByRole("button", { name: "Refresh tools" });
  fireEvent.click(refresh);
  expect(refresh).toBeDisabled();
  expect(refresh).toHaveAttribute("aria-busy", "true");
  expect(panel.queryByText("Tools refreshed.")).not.toBeInTheDocument();
  act(() => { vi.runOnlyPendingTimers(); });
  expect(refresh).toBeEnabled();
  expect(refresh).not.toHaveAttribute("aria-busy", "true");
  expect(panel.queryByText("Tools refreshed.")).not.toBeInTheDocument();
});

test("registered OAuth credentials are editable directly in the authentication tab", () => {
  render(<McpServicesStory scenario="connected" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage HubSpot" }));
  expect(screen.getByRole("dialog", { name: "HubSpot" })).toBeVisible();
  expect(screen.getByLabelText("Client ID")).toBeVisible();
  expect(screen.getByLabelText("Client secret")).toHaveAttribute("type", "password");
  expect(screen.getByRole("button", { name: "Reconnect" })).toBeEnabled();
});

test.each(["Cal.com", "HubSpot"])("%s keeps modal actions unchanged across tabs and credential edits", (name) => {
  render(<McpServicesStory scenario="connected" />);
  fireEvent.click(screen.getByRole("button", { name: `Manage ${name}` }));
  const dialog = screen.getByRole("dialog", { name });
  const footer = within(dialog.querySelector("footer")!);
  const actions = () => footer.getAllByRole("button").map(button => button.textContent);
  expect(actions()).toEqual(["Disconnect", "Close"]);

  if (name === "HubSpot") {
    fireEvent.change(screen.getByLabelText("Client ID"), { target: { value: "updated-client" } });
    const authentication = within(screen.getByRole("tabpanel", { name: "Authentication" }));
    expect(authentication.getByRole("button", { name: "Save changes" })).toBeEnabled();
    expect(actions()).toEqual(["Disconnect", "Close"]);
  }

  fireEvent.mouseDown(screen.getByRole("tab", { name: "Tools" }), { button: 0, ctrlKey: false });
  expect(actions()).toEqual(["Disconnect", "Close"]);
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Authentication" }), { button: 0, ctrlKey: false });
  expect(actions()).toEqual(["Disconnect", "Close"]);
  if (name === "HubSpot") expect(screen.getByLabelText("Client ID")).toHaveValue("updated-client");
});
