import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { OAuthConsentStory } from "./OAuthConsentStory";

beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); vi.restoreAllMocks(); window.history.replaceState({}, "", "/"); });

test("allow and deny show product copy without protocol or Storybook annotations", () => {
  const location = window.location.href;
  const { unmount } = render(<OAuthConsentStory />);
  fireEvent.click(screen.getByRole("button", { name: "Allow connection" }));
  expect(screen.getByRole("heading", { name: "Access approved" })).toHaveFocus();
  expect(screen.getByText("Continue in Codex to finish connecting to Vxpipe.")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Back to Vxpipe" })).toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Manage connected clients" })).toBeInTheDocument();
  expect(screen.queryByText(/HTTP|Storybook|EXAMPLE_CODE|What happens next|client controls/)).not.toBeInTheDocument();
  unmount();
  render(<OAuthConsentStory />);
  fireEvent.click(screen.getByRole("button", { name: "Deny" }));
  expect(screen.getByRole("heading", { name: "Connection declined" })).toHaveFocus();
  expect(screen.getByText("Codex wasn’t given new access to your Vxpipe account.")).toBeInTheDocument();
  expect(screen.queryByText(/HTTP|Storybook|access_denied|What happens next|client controls/)).not.toBeInTheDocument();
  expect(window.location.href).toBe(location);
});

test("the approved page returns to Console home with its primary action", () => {
  render(<OAuthConsentStory initialStep="allowed" />);
  fireEvent.click(screen.getByRole("button", { name: "Back to Vxpipe" }));
  expect(screen.getByRole("heading", { name: "Tenants", level: 1 })).toBeInTheDocument();
});

test("consent links to a working connected clients destination", async () => {
  render(<OAuthConsentStory />);
  fireEvent.click(screen.getByRole("link", { name: "My account → Connected clients" }));
  expect(await screen.findByRole("heading", { name: "Connected clients", level: 1 })).toBeInTheDocument();
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Access revoked for Codex");
  expect(screen.queryByRole("button", { name: "Revoke access for Codex" })).not.toBeInTheDocument();
});

test("client metadata provides a logo and website, with a fallback for failed logos", () => {
  render(<OAuthConsentStory />);
  const logo = screen.getByRole("img", { name: "Codex logo" });
  expect(logo).toHaveAttribute("referrerpolicy", "no-referrer");
  expect(screen.getByRole("link", { name: /chatgpt.com\/codex/ })).toHaveAttribute("href", "https://chatgpt.com/codex");
  fireEvent.error(logo);
  expect(screen.queryByRole("img", { name: "Codex logo" })).not.toBeInTheDocument();
  expect(screen.getByRole("img", { name: "Client icon" })).toBeInTheDocument();
});

test("DCR without optional branding still has a usable identity and consent actions", () => {
  render(<OAuthConsentStory clientKind="dcr" />);
  expect(screen.getByRole("img", { name: "Client icon" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Connect Research assistant to Vxpipe?" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Allow connection" })).toBeEnabled();
});

test("all-tenant and empty authority states do not imply a narrower or invented grant", () => {
  const { unmount } = render(<OAuthConsentStory access="all-tenants" />);
  expect(screen.getByText("All tenants, including future tenants")).toBeInTheDocument();
  unmount();
  render(<OAuthConsentStory access="empty" />);
  expect(screen.getByText("No action permissions available")).toBeInTheDocument();
  expect(screen.queryByText("Read calls")).not.toBeInTheDocument();
});
