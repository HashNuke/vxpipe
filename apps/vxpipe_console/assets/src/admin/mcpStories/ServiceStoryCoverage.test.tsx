import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { SetupStory } from "../stories/SetupStory";
import { NavigationServices } from "../navigation/NavigationServices";
import { ServiceInventoryStory } from "../stories/ResourceStories";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

function browseAndChoose() {
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  expect(screen.getByRole("heading", { name: /^(Platform )?Integrations$/ })).toBeVisible();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Connect Deepgram" }));
  const dialog = within(screen.getByRole("dialog"));
  expect(dialog.getByRole("heading", { name: "Connect Deepgram" })).toBeVisible();
  expect(dialog.queryByRole("combobox", { name: "Service" })).not.toBeInTheDocument();
  expect(dialog.getByLabelText("API key", { exact: true })).toBeVisible();
}

test("the existing Choose services story browses before entering credentials", () => {
  render(<SetupStory scenario="choose-services" theme="dark" />);
  browseAndChoose();
});

test("platform stories use the directory without tenant MCP categories", () => {
  render(<SetupStory scenario="platform-services" theme="dark" />);
  browseAndChoose();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
  const nav = within(screen.getByRole("navigation", { name: "Integration categories" }));
  expect(nav.getAllByRole("link")).toHaveLength(3);
});

test("navigation Integrations opens saved credentials from the directory", () => {
  render(<NavigationServices tenant={{ key: "demo", name: "Demo" }} onNavigate={() => undefined} />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.click(screen.getByRole("button", { name: "Edit Deepgram" }));
  expect(screen.getByRole("dialog", { name: "Manage Deepgram" })).toBeVisible();
});

test("legacy inventory stories share the directory workflow", () => {
  render(<ServiceInventoryStory scenario="empty" theme="dark" />);
  browseAndChoose();
});

test("legacy inventory opens the saved connection from its directory row", () => {
  render(<ServiceInventoryStory scenario="populated" theme="dark" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.click(screen.getByRole("button", { name: "Edit Deepgram" }));
  expect(screen.getByRole("dialog", { name: "Manage Deepgram" })).toBeVisible();
});

test("existing validation stories retain their errors in a fixed-provider dialog", () => {
  render(<SetupStory scenario="validation-error" theme="dark" />);
  const dialog = within(screen.getByRole("dialog"));
  expect(dialog.getByRole("alert")).toHaveTextContent("Google rejected this API key");
  expect(dialog.queryByRole("combobox", { name: "Service" })).not.toBeInTheDocument();
  expect(dialog.getByRole("heading", { name: "Connect Google AI Studio" })).toBeVisible();
});


test("an unavailable local inventory does not advertise new connections in the directory", () => {
  render(<ServiceInventoryStory scenario="unavailable" theme="dark" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  expect(screen.getByText("Connection status unavailable")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect Deepgram" })).not.toBeInTheDocument();
});
