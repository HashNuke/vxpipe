import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { AuthenticationJourney } from "./AuthenticationJourney";

beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); vi.restoreAllMocks(); });

test("the account preview exposes revocation and preserves it across account navigation", async () => {
  render(<AuthenticationJourney initialPath="/account/connections" followLocation={false} />);
  expect(screen.getByRole("heading", { name: "Connected clients", level: 1 })).toBeVisible();
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Access revoked for Codex");
  fireEvent.click(screen.getByRole("link", { name: "Account" }));
  expect(await screen.findByRole("button", { name: "Revoke access for Research assistant" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Revoke access for Codex" })).not.toBeInTheDocument();
});

test("a failed revoke keeps the client available for retry", async () => {
  render(<AuthenticationJourney initialPath="/account/connections" followLocation={false} connectionsScenario="revoke-failure" />);
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Try again");
  expect(screen.getByRole("button", { name: "Revoke access for Codex" })).toBeEnabled();
});
