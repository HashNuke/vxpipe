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
  expect(screen.getByLabelText("Authentication type")).toHaveValue(method);
  expect(screen.getByRole("button", { name: method === "basic" ? "Authentication: Basic authentication" : "Authentication: OAuth · Registered client" })).toBeVisible();
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
  expect(screen.getByLabelText("Authentication")).toBeVisible();
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Client metadata URL")).not.toBeInTheDocument();
});

test("an unlisted MCP gets its displayed name from server metadata without a name field", async () => {
  render(<McpServicesStory scenario="custom" />);
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: "https://office.example.test/mcp" } });
  fireEvent.change(screen.getByLabelText("Authentication"), { target: { value: "none" } });
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
