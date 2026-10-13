import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { TenantPicker } from "./TenantPicker";
afterEach(cleanup);
test.each(["tenant", "directory"])("%s selection notifies the search owner that the picker closed", target => {
  const onOpenChange = vi.fn();
  render(<TenantPicker tenants={[{ id: "AAAAAAAAAAAAAAAA", key: "AAAAAAAAAAAAAAAA", name: "Acme" }]} directoryPath="/my-tenants" onNavigate={vi.fn()} onRetry={vi.fn()} onOpenChange={onOpenChange} />);
  fireEvent.click(screen.getByRole("combobox", { name: "Switch tenant" }));
  expect(onOpenChange).toHaveBeenLastCalledWith(true);
  fireEvent.click(target === "tenant" ? screen.getByRole("option", { name: /Acme/ }) : screen.getByRole("link", { name: "View my tenants" }));
  expect(onOpenChange).toHaveBeenLastCalledWith(false);
});
