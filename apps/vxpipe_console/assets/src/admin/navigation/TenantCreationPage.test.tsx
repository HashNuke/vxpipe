import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { TenantCreationForm } from "./TenantCreationPage";
afterEach(cleanup);
test("a failed creation keeps the entered name and allows another submission", async () => {
  const create = vi.fn().mockRejectedValueOnce(new Error("unavailable")).mockResolvedValue(undefined);
  render(<TenantCreationForm onCreate={create} onCancel={() => {}} />);
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "Support" } });
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Could not create the tenant. Please try again.");
  expect(screen.getByRole("textbox", { name: "Name" })).toHaveValue("Support");
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  expect(create).toHaveBeenCalledTimes(2);
});
