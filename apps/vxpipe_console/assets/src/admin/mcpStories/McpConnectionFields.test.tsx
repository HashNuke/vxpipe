import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { McpServicesStory } from "./McpServicesStory";
import { AuthenticationFields } from "./AuthenticationFields";
import { draftFor, presets } from "./fixtures";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test.each(["basic", "oauth"] as const)("managing a custom %s connection retains its authentication choices without revealing credentials", async method => {
  render(<McpServicesStory scenario={method === "basic" ? "custom-basic" : "custom-oauth"} />);
  if (method === "basic") {
    fireEvent.change(screen.getByLabelText("Username"), { target: { value: "example-user" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "illustrative-password" } });
  } else {
    fireEvent.change(screen.getByLabelText("Grant type"), { target: { value: "client_credentials" } });
    fireEvent.change(screen.getByLabelText("Client authentication"), { target: { value: "client_secret_post" } });
    fireEvent.change(screen.getByLabelText("Client ID"), { target: { value: "example-client" } });
    fireEvent.change(screen.getByLabelText("Client secret"), { target: { value: "illustrative-secret" } });
  }
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByText("Office tools is connected")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fireEvent.click(screen.getByRole("button", { name: "Manage Office tools" }));
  expect(screen.getByRole("combobox", { name: "Authentication Type" })).toHaveValue(method);
  expect(screen.getByRole("button", { name: method === "basic" ? "Authentication: HTTP Basic" : "Authentication: OAuth - Own client" })).toBeVisible();
  expect(screen.getByLabelText(method === "basic" ? "Password" : "Client secret")).toHaveValue("");
  if (method === "oauth") {
    expect(screen.getByLabelText("Grant type")).toHaveValue("client_credentials");
    expect(screen.getByLabelText("Client authentication")).toHaveValue("client_secret_post");
    expect(screen.queryByRole("button", { name: "Reconnect" })).not.toBeInTheDocument();
  }
});

test.each(["calcom", "calendly"] as const)("%s uses directory configuration without asking for managed fields", async scenario => {
  render(<McpServicesStory scenario={scenario} />);
  const dialog = within(screen.getByRole("dialog"));
  for (const label of ["Connection name", "MCP server URL", "Authentication", "Callback URL", "Client metadata URL"])
    expect(dialog.queryByLabelText(label)).not.toBeInTheDocument();
  expect(dialog.queryByRole("combobox")).not.toBeInTheDocument();
  fireEvent.click(dialog.getByRole("button", { name: "Connect" }));
  expect(await screen.findByRole("button", { name: "Simulate authorization" })).toBeVisible();
});

test("a listed MCP with manual registration asks only for client credentials and callback setup", () => {
  render(<McpServicesStory scenario="google-calendar" />);
  expect(screen.getByLabelText("Client ID")).toBeVisible();
  expect(screen.getByLabelText("Client secret")).toHaveAttribute("type", "password");
  expect(screen.getByLabelText("Callback URL")).toHaveValue("https://voice.example.test/oauth/mcp/callback");
  for (const label of ["Connection name", "MCP server URL", "Authentication", "Authentication type", "Grant type", "Client authentication"])
    expect(screen.queryByLabelText(label)).not.toBeInTheDocument();
});

test.each(["cimd", "dcr"] as const)("custom %s setup also hides managed callback metadata", scenario => {
  render(<McpServicesStory scenario={scenario} />);
  expect(screen.getByLabelText("MCP server URL")).toBeVisible();
  expect(screen.getByLabelText("Authentication Type")).toBeVisible();
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Client metadata URL")).not.toBeInTheDocument();
});

test("an unlisted MCP gets its displayed name from server metadata without a name field", async () => {
  render(<McpServicesStory scenario="custom" />);
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: "https://office.example.test/mcp" } });
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "none" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByText("Office tools is connected")).toBeVisible();
});

test("a directory bearer template exposes the secret but no authentication selector", () => {
  const draft = draftFor({ ...presets[0], auth: "custom", customAuth: "bearer" });
  render(<AuthenticationFields draft={draft} update={() => {}} />);
  expect(screen.getByLabelText("Bearer token")).toHaveAttribute("type", "password");
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
});

test("saved directory MCPs use their service name and cannot edit catalog endpoints", () => {
  render(<McpServicesStory scenario="connected" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Cal.com" }));
  expect(screen.getByRole("dialog", { name: "Cal.com" })).toBeVisible();
  expect(screen.getByRole("tab", { name: "Authentication" })).toHaveAttribute("aria-selected", "true");
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
});

test("custom MCP authentication methods are selected directly in one dropdown", () => {
  render(<McpServicesStory scenario="custom" />);
  const authentication = screen.getByRole("combobox", { name: "Authentication Type" });
  expect(within(authentication).getAllByRole("option").map(option => option.textContent)).toEqual([
    "Select authentication type", "OAuth - CIMD", "OAuth - DCR", "OAuth - Own client",
    "Bearer token", "Custom headers", "HTTP Basic", "No authentication",
  ]);
  for (const [method, field] of [["oauth", "Client ID"], ["bearer", "Bearer token"], ["headers", "Header name 1"], ["basic", "Username"]]) {
    fireEvent.change(authentication, { target: { value: method } });
    expect(authentication).toHaveValue(method);
    expect(screen.queryByLabelText("Authentication type")).not.toBeInTheDocument();
    expect(screen.getByLabelText(field)).toBeVisible();
  }
  fireEvent.change(authentication, { target: { value: "none" } });
  expect(screen.queryByLabelText("Username")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Client ID")).not.toBeInTheDocument();
});

test("custom headers shows its header editor without an empty additional parameters section", () => {
  render(<McpServicesStory scenario="custom-headers" />);
  expect(screen.getByLabelText("Header name 1")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Additional parameters" })).not.toBeInTheDocument();
});

test.each(["cimd", "dcr"] as const)("%s only exposes user-supplied setup fields", method => {
  render(<McpServicesStory scenario={method} />);
  expect(screen.queryByRole("button", { name: "OAuth endpoints and scopes" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Additional parameters" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Dynamic registration settings" })).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Registration URL")).not.toBeInTheDocument();
  if (method === "dcr") {
    expect(screen.getByLabelText("Initial registration token")).toHaveAttribute("type", "password");
  } else {
    expect(screen.queryByLabelText("Initial registration token")).not.toBeInTheDocument();
  }
});

test.each(["cimd", "dcr"] as const)("switching to %s ignores hidden manual overrides", async method => {
  render(<McpServicesStory scenario="custom-oauth" />);
  fireEvent.click(screen.getByRole("button", { name: "OAuth endpoints and scopes" }));
  fireEvent.change(screen.getByLabelText("Token URL"), { target: { value: "invalid" } });
  fireEvent.click(screen.getByRole("button", { name: "Additional parameters" }));
  fireEvent.click(screen.getByRole("button", { name: "Add header" }));
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: method } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByRole("button", { name: "Simulate authorization" })).toBeVisible();
});

test("bearer and Basic start without implicit API-key headers", () => {
  render(<McpServicesStory scenario="custom-bearer" />);
  fireEvent.click(screen.getByRole("button", { name: "Additional parameters" }));
  expect(screen.queryByLabelText("Header name 1")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "basic" } });
  expect(screen.queryByLabelText("Header name 1")).not.toBeInTheDocument();
});

test.each(["bearer", "basic", "oauth"] as const)("switching from Custom headers to %s discards authentication headers", method => {
  render(<McpServicesStory scenario="custom-headers" />);
  fireEvent.change(screen.getByLabelText("Header value 1"), { target: { value: "preview-api-key" } });
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: method } });
  fireEvent.click(screen.getByRole("button", { name: "Additional parameters" }));
  expect(screen.queryByLabelText("Header name 1")).not.toBeInTheDocument();
  expect(screen.queryByDisplayValue("preview-api-key")).not.toBeInTheDocument();
});

test("additional headers are scoped to their authentication method, including switches through managed methods", () => {
  render(<McpServicesStory scenario="custom-bearer" />);
  fireEvent.click(screen.getByRole("button", { name: "Additional parameters" }));
  fireEvent.click(screen.getByRole("button", { name: "Add header" }));
  fireEvent.change(screen.getByLabelText("Header name 1"), { target: { value: "X-Workspace" } });
  fireEvent.change(screen.getByLabelText("Header value 1"), { target: { value: "preview-workspace" } });
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "cimd" } });
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "headers" } });
  expect(screen.getByLabelText("Header name 1")).toHaveValue("X-API-Key");
  expect(screen.getByLabelText("Header value 1")).toHaveValue("");
});
