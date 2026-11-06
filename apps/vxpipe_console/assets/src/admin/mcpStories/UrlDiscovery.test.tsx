import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";
afterEach(() => { cleanup(); vi.useRealTimers(); vi.restoreAllMocks(); window.history.replaceState({}, "", "/"); });
const enter = (value: string) => fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value } });
const advance = async (ms: number) => act(async () => { await vi.advanceTimersByTimeAsync(ms); });
test("URL discovery prefills editable OAuth fields without automatic options or network requests", async () => {
  vi.useFakeTimers();
  const fetch = vi.spyOn(window, "fetch");
  render(<McpServicesStory scenario="custom" />);
  expect(screen.queryByRole("option", { name: "Discover automatically" })).not.toBeInTheDocument();
  enter("https://office.example.test/mcp");
  await advance(400);
  expect(screen.getByRole("status")).toHaveTextContent("Checking MCP server");
  await advance(400);
  expect(screen.getByRole("status")).toHaveTextContent("Discovering OAuth settings");
  await advance(400);
  expect(screen.getByRole("status")).toHaveTextContent("Settings discovered");
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("cimd");
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "oauth" } });
  fireEvent.click(screen.getByText("OAuth endpoints and scopes"));
  expect(screen.queryByLabelText("Endpoint configuration")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Token URL")).toHaveValue("https://office.example.test/oauth/token");
  fireEvent.change(screen.getByLabelText("Token URL"), { target: { value: "https://office.example.test/custom/token" } });
  expect(screen.getByLabelText("Token URL")).toHaveValue("https://office.example.test/custom/token");
  expect(fetch).not.toHaveBeenCalled();
});
test("URL changes discard previous settings and pending results while preserving new manual edits", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="custom" />);
  enter("https://old.example.test/mcp");
  await advance(800);
  enter("https://new.example.test/mcp");
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "bearer" } });
  fireEvent.change(screen.getByLabelText("Bearer token"), { target: { value: "preview-secret" } });
  await advance(1200);
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("bearer");
  expect(screen.getByLabelText("Bearer token")).toHaveValue("preview-secret");
  enter("https://third.example.test/mcp");
  expect(screen.queryByDisplayValue("preview-secret")).not.toBeInTheDocument();
  await advance(1200);
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "oauth" } });
  fireEvent.click(screen.getByText("OAuth endpoints and scopes"));
  expect(screen.getByLabelText("Token URL")).toHaveValue("https://third.example.test/oauth/token");
});
test("failed discovery offers retry and manual configuration without assuming anonymous access", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="discovery-failed" />);
  await advance(1200);
  expect(screen.getByRole("status")).toHaveTextContent("Could not discover settings");
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("auto");
  expect(screen.getByRole("button", { name: "Connect" })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Retry discovery" }));
  await advance(400);
  expect(screen.getByRole("status")).toHaveTextContent("Checking MCP server");
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "none" } });
  expect(screen.getByRole("button", { name: "Connect" })).toBeEnabled();
});
test("invalid URLs do not start discovery and closing cancels pending discovery", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="custom" />);
  enter("https://");
  await advance(1200);
  expect(screen.queryByRole("status")).not.toBeInTheDocument();
  enter("https://office.example.test/mcp");
  await advance(400);
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  await advance(1200);
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("manual endpoint edits are validated without a configuration mode selector", () => {
  render(<McpServicesStory scenario="cimd" />);
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "oauth" } });
  fireEvent.click(screen.getByText("OAuth endpoints and scopes"));
  fireEvent.change(screen.getByLabelText("Client ID"), { target: { value: "preview-client" } });
  fireEvent.change(screen.getByLabelText("Client secret"), { target: { value: "preview-secret" } });
  fireEvent.change(screen.getByLabelText("Token URL"), { target: { value: "http://insecure.example.test/token" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(screen.getByRole("alert")).toHaveTextContent("OAuth URLs must be complete HTTPS URLs");
});

test("editing a saved custom URL discovers new settings before Save changes", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="no-auth" />);
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await advance(400);
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fireEvent.click(screen.getByRole("button", { name: "Manage Office tools" }));
  enter("https://replacement.example.test/mcp");
  expect(screen.getByRole("button", { name: "Save changes" })).toBeDisabled();
  await advance(1200);
  expect(screen.getByRole("status")).toHaveTextContent("Settings discovered");
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("cimd");
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  await advance(400);
  expect(screen.getByRole("button", { name: "Simulate authorization" })).toBeVisible();
});

test("machine grants ignore a hidden authorization URL left by the code grant", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="custom-oauth" />);
  fireEvent.click(screen.getByRole("button", { name: "OAuth endpoints and scopes" }));
  fireEvent.change(screen.getByLabelText("Authorization URL"), { target: { value: "invalid" } });
  fireEvent.change(screen.getByLabelText("Grant type"), { target: { value: "client_credentials" } });
  fireEvent.change(screen.getByLabelText("Client ID"), { target: { value: "preview-client" } });
  fireEvent.change(screen.getByLabelText("Client secret"), { target: { value: "preview-secret" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  await advance(400);
  expect(screen.getByText("Office tools is connected")).toBeVisible();
});

test("pending discovery preserves manual OAuth endpoint and scope edits for the same URL", async () => {
  vi.useFakeTimers();
  render(<McpServicesStory scenario="custom" />);
  enter("https://office.example.test/mcp");
  await advance(400);
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "oauth" } });
  fireEvent.click(screen.getByRole("button", { name: "OAuth endpoints and scopes" }));
  fireEvent.change(screen.getByLabelText("Token URL"), { target: { value: "https://office.example.test/custom/token" } });
  fireEvent.change(screen.getByLabelText("Scopes"), { target: { value: "custom:read" } });
  await advance(800);
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("oauth");
  expect(screen.getByLabelText("Token URL")).toHaveValue("https://office.example.test/custom/token");
  expect(screen.getByLabelText("Scopes")).toHaveValue("custom:read");
});
