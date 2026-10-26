import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { AuthenticationFields } from "./AuthenticationFields";
import { draftFor, presets } from "./fixtures";
import { directoryPreset, remoteCatalog, type RemoteMcpIntegration } from "./remoteDirectory";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); });

test("directory setup metadata maps to the connection presentation", () => {
  const entry = { ...remoteCatalog.integrations[0], setup_url: "https://example.test/setup", documentation_url: "https://example.test/docs", setup_notes: "Register an OAuth client." } as RemoteMcpIntegration;
  expect(directoryPreset(entry, "test")).toMatchObject({ setupUrl: entry.setup_url, docs: entry.documentation_url, setupNotes: entry.setup_notes });
});

test.each(Array.from({ length: 8 }, (_, mask) => mask))("optional setup metadata combination %i displays only supplied content", mask => {
  const setupNotes = mask & 1 ? "Register an OAuth client." : undefined;
  const setupUrl = mask & 2 ? "https://example.test/setup" : undefined;
  const docs = mask & 4 ? "https://example.test/docs" : undefined;
  const { container } = render(<AuthenticationFields draft={draftFor({ ...presets[0], setupNotes, setupUrl, docs })} update={() => {}} />);
  if (setupNotes) expect(screen.getByText(setupNotes)).toBeVisible();
  else expect(screen.queryByText("Register an OAuth client.")).not.toBeInTheDocument();
  for (const [name, url] of [["Setup", setupUrl], ["Documentation", docs]]) {
    if (url) {
      const link = screen.getByRole("link", { name });
      expect(link).toHaveAttribute("href", url);
      expect(link).toHaveAttribute("target", "_blank");
    } else expect(screen.queryByRole("link", { name })).not.toBeInTheDocument();
  }
  if (!mask) expect(container.querySelector(".mcp-provider-note")).not.toBeInTheDocument();
});

test.each(["connect", "manage"])("%s HubSpot uses setup notes and a Documentation link", action => {
  render(<McpServicesStory scenario={action === "connect" ? "hubspot" : "connected"} />);
  if (action === "manage") fireEvent.click(screen.getByRole("button", { name: "Manage HubSpot" }));
  const dialog = within(screen.getByRole("dialog"));
  expect(dialog.getByText("Create an MCP connector in HubSpot, then enter its client ID and secret.")).toBeVisible();
  expect(dialog.getByRole("link", { name: "Documentation" })).toBeVisible();
  expect(dialog.queryByRole("link", { name: "Setup instructions" })).not.toBeInTheDocument();
  expect(dialog.getByLabelText("Callback URL")).toHaveAttribute("readonly");
  expect(dialog.getByRole("button", { name: "Copy callback url" })).toBeEnabled();
});
