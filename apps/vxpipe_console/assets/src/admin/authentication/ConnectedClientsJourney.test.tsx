import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { NavigationJourney } from "../navigation/NavigationJourney";
import { AuthenticationStory } from "../stories/AuthenticationStory";

beforeEach(() => { vi.spyOn(window, "scrollTo").mockImplementation(() => undefined); });
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/"); vi.restoreAllMocks(); });

test("personal pages use Settings and preserve revocation across account navigation", async () => {
  render(<AuthenticationStory initialPath="/account/connections" followLocation={false} />);
  expect(screen.getByRole("heading", { name: "Your connections", level: 1 })).toBeVisible();
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Revoke access" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Access revoked for Codex");
  fireEvent.click(screen.getByRole("link", { name: "Your account" }));
  expect(screen.getByRole("heading", { name: "Your account" })).toBeVisible();
  expect(screen.getByLabelText("Email")).toHaveValue("owner@example.test");
  expect(screen.queryByRole("button", { name: /Revoke access/ })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("link", { name: "Your connections" }));
  expect(await screen.findByRole("button", { name: "Revoke access for Research assistant" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Revoke access for Codex" })).not.toBeInTheDocument();
});

test("members can edit their own account and manage connections without administrative pages", async () => {
  render(<AuthenticationStory actor="member" initialPath="/account" followLocation={false} />);
  expect(screen.getByLabelText("Email")).toHaveValue("member@example.test");
  expect(screen.queryByRole("link", { name: "Users" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Roles" })).not.toBeInTheDocument();
  expect(screen.getByRole("navigation", { name: "For you" })).toBeVisible();
  fireEvent.click(screen.getByRole("checkbox", { name: "Change password" }));
  expect(screen.getByLabelText("New password")).toBeVisible();
  fireEvent.click(screen.getByRole("link", { name: "Your connections" }));
  expect(await screen.findByRole("button", { name: "Revoke access for Codex" })).toBeVisible();
});

test("a failed revoke keeps the confirmation available for retry or cancellation", async () => {
  render(<AuthenticationStory initialPath="/account/connections" followLocation={false} connectionsScenario="revoke-failure" />);
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Codex" }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Revoke access" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Try again");
  expect(within(screen.getByRole("dialog")).getByRole("button", { name: "Revoke access" })).toBeEnabled();
});


test.each([AuthenticationStory, NavigationJourney])("personal account preview saves email and signs out after a password change (%#)", async (Journey) => {
  render(<Journey initialPath="/account" />);
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "updated@example.test" } });
  fireEvent.change(screen.getByLabelText("Current password"), { target: { value: "current password" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  expect(await screen.findByText("Account updated.")).toBeVisible();
  fireEvent.click(screen.getByRole("link", { name: "Your connections" }));
  fireEvent.click(screen.getByRole("link", { name: "Your account" }));
  expect(screen.getByLabelText("Email")).toHaveValue("updated@example.test");
  fireEvent.click(screen.getByRole("checkbox", { name: "Change password" }));
  fireEvent.change(screen.getByLabelText("Current password"), { target: { value: "current password" } });
  fireEvent.change(screen.getByLabelText("New password"), { target: { value: "replacement long password" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "replacement long password" } });
  fireEvent.click(screen.getByRole("button", { name: "Save changes" }));
  expect(await screen.findByRole("heading", { name: "Sign in to Vxpipe" })).toBeVisible();
});
