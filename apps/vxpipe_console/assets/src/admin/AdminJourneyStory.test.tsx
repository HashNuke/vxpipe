import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";

import { AdminJourneyStory } from "./AdminJourneyStory";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
});

test("links the tenant directory to definitions and back", () => {
  window.history.replaceState({}, "", "/iframe.html?id=admin-full-journey");
  render(<AdminJourneyStory theme="dark" />);

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  fireEvent.click(screen.getByRole("link", { name: /open demo workspace/i }));

  expect(
    screen.getByRole("heading", { name: "Call definitions" }),
  ).toBeVisible();
  expect(window.location.hash).toBe("#/admin/tenants/tn_demo_01");

  fireEvent.click(
    screen.getByRole("link", { name: /open delivery rescheduling/i }),
  );
  expect(window.location.pathname).toBe("/iframe.html");
  expect(window.location.hash).toBe(
    "#/admin/tenants/tn_demo_01/definitions/delivery-rescheduling",
  );
  expect(
    screen.getByRole("heading", { name: "Call definitions" }),
  ).toBeVisible();

  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));

  expect(screen.getByRole("heading", { name: "Tenants" })).toBeVisible();
  expect(window.location.hash).toBe("#/admin");
});
