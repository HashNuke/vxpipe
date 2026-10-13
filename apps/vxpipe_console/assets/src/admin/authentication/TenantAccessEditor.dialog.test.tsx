import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { TenantAccessEditor } from "./TenantAccessEditor";
import { roles, tenants } from "./fixtures";

afterEach(cleanup);

test("Add tenants opens a dialog without expanding the form", () => {
  const role = roles.find((item) => item.name === "Tenant Manager");
  if (!role) throw new Error("Tenant Manager fixture missing");
  const assignedRole = {
    ...role,
    grants: [
      { permission: "calls.read", scope: "assigned_tenants" as const },
      { permission: "call_specs.read", scope: "assigned_tenants" as const },
    ],
  };

  const { container } = render(
    <TenantAccessEditor
      role={assignedRole}
      tenants={tenants}
      value={[]}
      onChange={() => undefined}
    />,
  );

  fireEvent.click(screen.getByRole("button", { name: "Add tenants" }));

  const dialog = screen.getByRole("dialog", { name: "Add tenants" });
  expect(within(dialog).getByRole("searchbox", { name: "Search tenants" })).toBeVisible();
  expect(container.querySelector(".access-section > .access-picker")).not.toBeInTheDocument();
});
