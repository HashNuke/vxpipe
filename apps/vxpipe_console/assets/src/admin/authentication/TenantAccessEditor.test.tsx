import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, expect, test } from "vitest";
import { TenantAccessEditor } from "./TenantAccessEditor";
import { roles, tenants } from "./fixtures";
import type { Membership } from "./types";

afterEach(cleanup);
function Editor() {
  const [value, setValue] = useState<Membership[]>([]);
  return (
    <TenantAccessEditor
      role={roles[4]}
      tenants={tenants}
      value={value}
      onChange={setValue}
    />
  );
}
test("adds a searched tenant read-only, changes its access and removes it", () => {
  render(<Editor />);
  fireEvent.click(screen.getByRole("button", { name: "Add tenants" }));
  fireEvent.change(screen.getByRole("searchbox", { name: "Search tenants" }), {
    target: { value: "Northwind" },
  });
  fireEvent.click(screen.getByRole("checkbox", { name: /Northwind/ }));
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  const access = screen.getByRole("combobox", { name: "Access for Northwind" });
  expect(access).toHaveValue("read");
  fireEvent.change(access, { target: { value: "read_write" } });
  expect(
    screen.getByText("Calls: read & write · Call specs: read & write"),
  ).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Remove Northwind" }));
  expect(screen.getByText("No tenants assigned")).toBeVisible();
});
test("shows inherited all-tenant access with no membership picker", () => {
  render(
    <TenantAccessEditor
      role={roles[1]}
      tenants={tenants}
      value={[]}
      onChange={() => undefined}
    />,
  );
  expect(screen.getByText("All tenants — granted by role")).toBeVisible();
  expect(
    screen.queryByRole("button", { name: "Add tenants" }),
  ).not.toBeInTheDocument();
});
test("read-only viewers cannot edit assigned access", () => {
  render(
    <TenantAccessEditor
      role={roles[4]}
      tenants={tenants}
      value={[{ tenantId: tenants[0].id, access: "read" }]}
      readOnly
    />,
  );
  expect(screen.getByText(tenants[0].name)).toBeVisible();
  expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
  expect(screen.queryByRole("button")).not.toBeInTheDocument();
});
