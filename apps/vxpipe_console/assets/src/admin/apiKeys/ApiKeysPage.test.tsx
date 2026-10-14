import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ApiKeysPage } from "./ApiKeysPage";
import type { AccessKeysClient, AccessKey } from "./accessKeysApi";
afterEach(cleanup);
const key: AccessKey = { id: "key", name: "Backend", kind: "calls", lastFour: "abcd", createdAt: "2026-10-01T12:00:00Z", tenant: { key: "AAAAAAAAAAAAAAAA", name: "Acme" }, canRevoke: true };
function client(kinds: ("calls" | "full" | "platform")[] = ["calls", "full", "platform"]): AccessKeysClient {
  return { list: vi.fn().mockResolvedValue({ keys: [key], kinds, page: 1, hasNext: false }),
    tenants: vi.fn().mockResolvedValue({ tenants: [{ key: "BBBBBBBBBBBBBBBB", name: "Remote tenant" }], hasNext: false }),
    create: vi.fn().mockResolvedValue({ key, secret: "one-time-secret" }), revoke: vi.fn().mockResolvedValue(undefined) };
}
test("lists tenant in its own column and remotely selects the tenant for creation", async () => {
  const api = client();
  render(<ApiKeysPage api={api} />);
  expect(await screen.findByRole("columnheader", { name: "Tenant" })).toBeVisible();
  expect(screen.getByRole("cell", { name: "Acme" })).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  expect(screen.getByRole("button", { name: "Create API key" })).toBeDisabled();
  fireEvent.click(screen.getByRole("combobox", { name: "Tenant" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Search tenants" }), { target: { value: "remote" } });
  fireEvent.click(await screen.findByRole("option", { name: "Remote tenant" }));
  expect(api.tenants).toHaveBeenCalledWith("calls", "remote", 1, expect.any(AbortSignal));
  fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Integration" } });
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  await waitFor(() => expect(api.create).toHaveBeenCalledWith("Integration", "calls", "BBBBBBBBBBBBBBBB"));
  expect(await screen.findByDisplayValue("one-time-secret")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  expect(screen.queryByDisplayValue("one-time-secret")).not.toBeInTheDocument();
});
test("platform creation omits tenant and unauthorized types are absent", async () => {
  const api = client(["platform"]);
  render(<ApiKeysPage api={api} initialCreating />);
  const access = await screen.findByRole("combobox", { name: "Access type" });
  expect(within(access).queryByRole("option", { name: "Full Tenant Access" })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "Tenant" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  await waitFor(() => expect(api.create).toHaveBeenCalledWith("Application", "platform", null));
});
test("read-only inventory has no creation controls and revoke requires confirmation", async () => {
  const api = client([]);
  render(<ApiKeysPage api={api} />);
  await screen.findByRole("table", { name: "API keys" });
  expect(screen.queryByRole("button", { name: "Create API key" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Revoke Backend" }));
  expect(api.revoke).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Confirm revoke" }));
  await waitFor(() => expect(api.revoke).toHaveBeenCalledWith("key"));
});
