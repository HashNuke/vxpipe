import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { OAuthConsentStory } from "./OAuthConsentStory";

beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); vi.restoreAllMocks(); window.history.replaceState({}, "", "/"); });

test("an unavailable request offers a real recovery destination without approval controls", () => {
  render(<OAuthConsentStory initialStep="unavailable" />);
  expect(screen.getByRole("heading", { name: "This request can’t be completed" })).toBeInTheDocument();
  const back = screen.getByRole("link", { name: "Back to Vxpipe" });
  expect(back).toHaveAttribute("href", "/");
  expect(screen.queryByRole("button", { name: "Allow connection" })).not.toBeInTheDocument();
  fireEvent.click(back);
  expect(screen.getByRole("heading", { name: "Tenants", level: 1 })).toBeInTheDocument();
});

test.each(["Allow connection", "Deny"])("%s returns directly to the client", (decision) => {
  const location = window.location.href;
  render(<OAuthConsentStory />);
  fireEvent.click(screen.getByRole("button", { name: decision }));
  expect(screen.getByRole("status")).toHaveTextContent("Returned to Codex");
  expect(screen.queryByRole("link", { name: "Back to my app" })).not.toBeInTheDocument();
  expect(window.location.href).toBe(location);
});

test("consent links to a working connected clients destination", async () => {
  render(<OAuthConsentStory />);
  fireEvent.click(screen.getByRole("link", { name: "Settings → Your connections" }));
  expect(await screen.findByRole("heading", { name: "Your connections", level: 1 })).toBeInTheDocument();
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Revoke access" }));
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
