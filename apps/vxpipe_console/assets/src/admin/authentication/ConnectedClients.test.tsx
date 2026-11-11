import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { AuthenticationApi } from "./authenticationApi";
import { ConnectedClients } from "./ConnectedClients";

afterEach(cleanup);
const connection = { public_id: "grant-1", client_name: "Research client", resource: "https://vxpipe.test/mcp", inserted_at: "2026-10-16T00:00:00Z", expires_at: "2026-11-15T00:00:00Z" };

test("loads current connections and removes only successfully revoked access", async () => {
  const fetch = vi.fn().mockResolvedValueOnce(Response.json({ connections: [connection] })).mockResolvedValueOnce(new Response(null, { status: 204 }));
  render(<ConnectedClients api={new AuthenticationApi("csrf", fetch)} />);
  expect(await screen.findByText("Research client")).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Revoke access for Research client" }));
  const dialog = screen.getByRole("dialog", { name: "Revoke access to Research client?" });
  expect(fetch).toHaveBeenCalledTimes(1);
  fireEvent.click(within(dialog).getByRole("button", { name: "Revoke access" }));
  await waitFor(() => expect(screen.queryByText("Research client")).toBeNull());
  expect(screen.getByText("No connected clients.")).toBeTruthy();
  expect(screen.getByRole("status")).toHaveTextContent("Access revoked for Research client");
  expect(fetch).toHaveBeenLastCalledWith("/api/account/connections/grant-1", expect.objectContaining({ method: "DELETE", credentials: "same-origin", headers: expect.objectContaining({ "x-csrf-token": "csrf" }) }));
});

test("failed revocation leaves the connection visible and reports an actionable error", async () => {
  const fetch = vi.fn().mockResolvedValueOnce(Response.json({ connections: [connection] })).mockResolvedValueOnce(Response.json({ error: { code: "unavailable" } }, { status: 503 }));
  render(<ConnectedClients api={new AuthenticationApi("csrf", fetch)} />);
  fireEvent.click(await screen.findByRole("button", { name: "Revoke access for Research client" }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Revoke access" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Try again");
  expect(screen.getByRole("dialog")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.getByText("Research client")).toBeTruthy();
});

test("failed listing can be retried without hiding account details", async () => {
  const fetch = vi.fn().mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce(Response.json({ connections: [] }));
  render(<ConnectedClients api={new AuthenticationApi("csrf", fetch)} />);
  fireEvent.click(await screen.findByRole("button", { name: "Retry" }));
  expect(await screen.findByText("No connected clients.")).toBeTruthy();
});


test("cancelling revocation leaves access unchanged without sending a delete", async () => {
  const fetch = vi.fn().mockResolvedValue(Response.json({ connections: [connection] }));
  render(<ConnectedClients api={new AuthenticationApi("csrf", fetch)} />);
  const trigger = await screen.findByRole("button", { name: "Revoke access for Research client" });
  trigger.focus();
  fireEvent.click(trigger);
  expect(screen.getByRole("button", { name: "Cancel" })).toHaveFocus();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(trigger).toHaveFocus();
  expect(fetch).toHaveBeenCalledTimes(1);
  expect(screen.getByText("Research client")).toBeVisible();
});
