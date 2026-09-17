import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";

import { AdminApp } from "./AdminApp";

afterEach(cleanup);

test("mounts the protected admin shell with a CSRF-protected sign-out action", () => {
  const view = render(<AdminApp csrfToken="csrf-test-token" />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Sign out" })).toBeVisible();
  expect(view.container.querySelector('form[action="/auth/logout"]')).toHaveAttribute(
    "method",
    "post",
  );
  expect(view.container.querySelector('input[name="_csrf_token"]')).toHaveValue(
    "csrf-test-token",
  );
});
