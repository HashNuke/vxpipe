import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ApiKeysSetupPage } from "./ApiKeysSetupPage";

afterEach(cleanup);
const key = { id: "key-1", name: "Backend", kind: "calls" as const, lastFour: "9x2a" };

test("lists key names and only the final four characters", () => {
  render(<ApiKeysSetupPage tenantName="Acme" keys={[key]} creation={{ status: "idle" }} onCreate={vi.fn()} />);
  const table = screen.getByRole("table", { name: "API keys" });
  expect(within(table).getByRole("columnheader", { name: "Name" })).toBeVisible();
  expect(within(table).getByRole("cell", { name: "Backend" })).toBeVisible();
  expect(within(table).getByRole("cell", { name: "••••••••9x2a" })).toBeVisible();
  expect(screen.queryByText(/Give your application access/)).not.toBeInTheDocument();
  expect(screen.queryByText(/You can now set up call specs/)).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /Continue to Setup/ })).not.toBeInTheDocument();
});

test("successful creation returns to the list with a dismissible one-time reveal", () => {
  const onCreate = vi.fn();
  const view = render(<ApiKeysSetupPage tenantName="Acme" keys={[]} creation={{ status: "idle" }} onCreate={onCreate} />);
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  fireEvent.change(screen.getByLabelText("Key name"), { target: { value: "Backend" } });
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  expect(onCreate).toHaveBeenCalledWith("Backend", "calls");
  view.rerender(<ApiKeysSetupPage tenantName="Acme" keys={[key]} creation={{ status: "created", key, secret: "fixture-secret-9x2a" }} onCreate={onCreate} />);
  expect(screen.getByRole("heading", { name: "API Keys" })).toBeVisible();
  expect(screen.getByRole("table", { name: "API keys" })).toHaveTextContent("Backend");
  expect(screen.queryByLabelText("Key name")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  expect(screen.queryByDisplayValue("fixture-secret-9x2a")).not.toBeInTheDocument();
  expect(screen.getByRole("table", { name: "API keys" })).toHaveTextContent("••••••••9x2a");
});

test("cancel returns to the inventory without creating a key", () => {
  const onCreate = vi.fn();
  render(<ApiKeysSetupPage tenantName="Acme" keys={[]} creation={{ status: "idle" }} onCreate={onCreate} />);
  fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.getByRole("heading", { name: "API Keys" })).toBeVisible();
  expect(onCreate).not.toHaveBeenCalled();
});
