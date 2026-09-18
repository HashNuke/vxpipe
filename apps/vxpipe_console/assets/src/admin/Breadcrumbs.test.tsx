import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { Breadcrumbs } from "./Breadcrumbs";

afterEach(cleanup);

test.each([true, false])("caps every breadcrumb label without shortening its accessible name (compact=%s)", (compact) => {
  const root = "Installation administration and tenant directory";
  const tenant = "International delivery operations — Southeast Asia";
  const current = "Delivery rescheduling and exception handling";
  const selectTenant = vi.fn();

  render(
    <Breadcrumbs
      compact={compact}
      current="location"
      items={[
        { label: root, href: "/admin" },
        { label: tenant, href: "/admin/tenants/demo", onSelect: selectTenant },
        { label: current },
      ]}
    />,
  );

  for (const label of [root, tenant, current]) {
    const element = screen.getByText(label);
    expect(element).toHaveClass("max-w-[24ch]", "truncate");
    expect(element).toHaveAttribute("title", label);
  }
  const tenantLink = screen.getByRole("link", { name: tenant });
  expect(tenantLink).toHaveAttribute("href", "/admin/tenants/demo");
  fireEvent.click(tenantLink);
  expect(selectTenant).toHaveBeenCalledOnce();
  expect(screen.getByText(current)).toHaveAttribute("aria-current", "location");
});
