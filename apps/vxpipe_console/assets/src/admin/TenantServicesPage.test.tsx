import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";

import { serviceFixture } from "./serviceFixtures";
import { TenantServicesPage } from "./TenantServicesPage";

afterEach(cleanup);

test("separates credential storage from telephony service readiness", () => {
  render(<TenantServicesPage state={serviceFixture("populated")} />);

  expect(screen.getByRole("link", { name: "Services" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getAllByText("Credential stored")).not.toHaveLength(0);
  expect(screen.getByText("Not registered")).toBeVisible();
  expect(screen.getByText("Registered")).toBeVisible();
  expect(screen.getByText(/connection-primary/)).toHaveTextContent(
    "+14155550100",
  );
  expect(screen.getByText("No telephony service registered")).toBeVisible();
  expect(screen.queryByText(/••••|secret-value|api key:/i)).not.toBeInTheDocument();
});

test("opens and closes credential setup while restoring trigger focus", () => {
  render(<TenantServicesPage state={serviceFixture("populated")} />);
  const trigger = screen.getByRole("button", { name: "Add credential" });

  fireEvent.click(trigger);
  expect(screen.getByRole("dialog", { name: "Add credential" })).toBeVisible();
  expect(screen.getByLabelText("Provider")).toHaveFocus();
  screen.getByRole("button", { name: "Save credential" }).focus();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Tab" });
  expect(screen.getByRole("button", { name: "Close credential setup" })).toHaveFocus();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });

  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(trigger).toHaveFocus();
});

test("keeps empty and unavailable service inventories distinct", () => {
  const view = render(<TenantServicesPage state={serviceFixture("empty")} />);
  expect(screen.getByText("No services yet")).toBeVisible();
  expect(screen.getByRole("button", { name: "Add credential" })).toBeEnabled();

  view.rerender(<TenantServicesPage state={serviceFixture("unavailable")} />);
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Services could not be loaded",
  );
  expect(screen.getByRole("button", { name: "Add credential" })).toBeDisabled();
});

test("presents duplicate credentials as a conflict without a replace action", () => {
  render(<TenantServicesPage state={serviceFixture("duplicate-conflict")} />);

  expect(screen.getByRole("alert")).toHaveTextContent(
    "already exists",
  );
  expect(screen.queryByRole("button", { name: /replace|overwrite/i })).not.toBeInTheDocument();
});
