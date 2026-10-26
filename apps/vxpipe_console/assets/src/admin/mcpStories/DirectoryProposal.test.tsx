import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";
import { ServiceDirectory } from "./ServiceDirectory";
import { ServiceConnectionsPreview } from "./ServiceConnectionsPreview";
import { catalogWithProviders, remoteCatalog } from "./remoteDirectory";
import { directoryRequest } from "./directoryRequest";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); vi.restoreAllMocks(); });

test("browse requests use the deployed category parameter and global search removes it", () => {
  expect(directoryRequest({ category: "calendar" }).path).toContain("category=calendar");
  expect(directoryRequest({ category: "calendar", query: "Google" }).path).not.toContain("category");
});

test("healthy AI browsing uses the returned directory page, not the fallback catalog", () => {
  const catalog = catalogWithProviders(remoteCatalog);
  catalog.integrations = catalog.integrations.filter(item => item.kind === "mcp" || item.connection.provider_id === "google");
  render(<ServiceDirectory category="ai" onCategory={() => {}} categoryHref={id => `#/${id}`} connectedCount={0} renderConnected={() => null}
    search="" onSearch={() => {}} cursor={null} onCursor={() => {}} pageSize={20} previewPageState="ready"
    catalog={catalog} directoryState="ready" connectionState="ready" providerConnections={[]} mcpConnections={[]}
    onRetryDirectory={() => {}} onRetryConnections={() => {}} onSelect={() => {}} onProvider={() => {}} />);
  expect(screen.getByRole("button", { name: "Connect Google AI Studio" })).toBeVisible();
  expect(screen.queryByRole("article", { name: "OpenAI" })).not.toBeInTheDocument();
});

test("an outage immediately offers installed providers and clearly limits search until retry", () => {
  render(<McpServicesStory scenario="directory-unavailable" />);
  expect(screen.getByRole("button", { name: "Edit Deepgram" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Twilio" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect Google Calendar" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Google" } });
  expect(screen.getByText("Showing built-in AI and telephony services")).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Google AI Studio" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Connect other MCP" }));
  expect(screen.getByRole("dialog", { name: "Connect other MCP" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  fireEvent.click(screen.getByRole("button", { name: "Retry directory" }));
  expect(screen.getByRole("searchbox")).toHaveValue("Google");
  expect(screen.getByRole("button", { name: "Connect Google Calendar" })).toBeVisible();
});

test("the directory outage notice sits with category navigation and uses the concise fallback copy", () => {
  render(<McpServicesStory scenario="directory-unavailable" />);
  const sidebar = within(screen.getByRole("complementary", { name: "Integration categories and status" }));
  const notice = sidebar.getByRole("alert");
  expect(notice).toHaveTextContent("Integration directory unavailable");
  expect(notice).toHaveTextContent("Showing built-in AI and telephony services");
  expect(notice).not.toHaveTextContent("Your connected integrations");
  expect(sidebar.getByRole("button", { name: "Retry directory" })).toBeVisible();
});

test("an outage search with no installed matches remains a limited search, not a missing category", () => {
  render(<McpServicesStory scenario="directory-unavailable" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "unlisted office server" } });
  expect(screen.getByRole("heading", { name: "No matching installed integrations" })).toBeVisible();
  expect(screen.queryByText("Category unavailable")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Retry directory" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect other MCP" })).toBeVisible();
});

test("platform fallback never offers MCP setup even in an empty search", () => {
  render(<ServiceConnectionsPreview platform scenario="directory-unavailable" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Calendar" } });
  expect(screen.getByRole("heading", { name: "No matching installed integrations" })).toBeVisible();
  expect(screen.queryByText(/MCP listings/)).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
});

test("unsupported automatic registration hands the draft to manual OAuth client setup", () => {
  render(<McpServicesStory scenario="registration-required" />);
  const dialog = within(screen.getByRole("dialog"));
  expect(dialog.getByText("Register VxPipe with your provider")).toBeVisible();
  fireEvent.click(dialog.getByRole("button", { name: "Enter client details" }));
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  expect(screen.getByLabelText("MCP server URL")).toHaveValue("https://office.example.test/mcp");
  expect(screen.getByLabelText("Client ID")).toBeVisible();
  expect(screen.getByLabelText("Callback URL")).toHaveValue("https://voice.example.test/oauth/mcp/callback");
});

test("a failed discovery can be edited without losing the entered URL", () => {
  render(<McpServicesStory scenario="discovery-failed" />);
  fireEvent.click(screen.getByRole("button", { name: "Edit connection" }));
  expect(screen.getByLabelText("MCP server URL")).toHaveValue("https://office.example.test/mcp");
});

test("an installation URL issue blocks OAuth, but does not block bearer authentication", async () => {
  const fetch = vi.spyOn(window, "fetch");
  render(<McpServicesStory scenario="installation-url-required" />);
  expect(screen.getByRole("button", { name: "Connect" })).toBeDisabled();
  fireEvent.change(screen.getByLabelText("Authentication"), { target: { value: "custom" } });
  fireEvent.change(screen.getByLabelText("Bearer token"), { target: { value: "illustrative-token" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByText("Office tools is connected")).toBeVisible();
  expect(fetch).not.toHaveBeenCalled();
});

test("automatic discovery can connect an anonymous server without OAuth", async () => {
  render(<McpServicesStory scenario="discovery-no-auth" />);
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByText("Office tools is connected")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fireEvent.click(screen.getByRole("button", { name: "Manage Office tools" }));
  expect(within(screen.getByRole("dialog")).getByRole("combobox", { name: "Authentication" })).toHaveValue("none");
});
