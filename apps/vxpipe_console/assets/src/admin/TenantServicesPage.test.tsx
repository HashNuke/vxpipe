import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";

import { serviceFixture } from "./serviceFixtures";
import { TenantServicesPage } from "./TenantServicesPage";
import { formatAdminLocalTimestamp } from "./formatAdminTimestamp";

afterEach(cleanup);

test("shows safe credential previews and compact update times", () => {
  render(<TenantServicesPage state={serviceFixture("populated")} />);

  expect(screen.getByRole("link", { name: "Services" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(
    screen.getByRole("img", { name: "Google AI Studio service logo" }),
  ).toBeVisible();
  expect(
    screen.getByRole("img", { name: "Deepgram service logo" }),
  ).toBeVisible();
  expect(screen.getByText("Deepgram").closest("li")).toHaveTextContent("Speech-to-text");
  expect(screen.getByText("Deepgram").closest("li")).toHaveTextContent("Text-to-speech");
  expect(screen.getByText("Telnyx").closest("li")).toHaveTextContent("Telephony");
  expect(
    screen.getByRole("img", { name: "Google AI Studio service logo" }),
  ).toHaveAttribute("data-logo-source", "official");
  expect(
    screen
      .getByRole("img", { name: "Google AI Studio service logo" })
      .querySelector("img"),
  ).toHaveAttribute("src", expect.stringContaining("google.png"));
  expect(
    screen.getByRole("img", { name: "Google Vertex AI service logo" }),
  ).toHaveAttribute("data-logo-source", "official");
  expect(
    screen.getByRole("img", { name: "Telnyx service logo" }),
  ).toHaveAttribute("data-logo-source", "official");
  expect(screen.getByText("Credentials")).toBeVisible();
  expect(screen.getAllByText("API key:")).not.toHaveLength(0);
  expect(screen.getByText("****8c4a")).toBeVisible();
  expect(screen.getByText("Account SID:")).toBeVisible();
  expect(screen.getByText("****4566")).toBeVisible();
  expect(screen.getByText("Account SID:").parentElement).toHaveClass(
    "font-mono",
    "text-xs",
    "text-[var(--admin-muted)]",
  );
  expect(screen.getByText("Auth token:")).toBeVisible();
  expect(screen.getByText("******")).toBeVisible();
  expect(screen.queryByText("Credential stored")).not.toBeInTheDocument();
  expect(screen.queryByText("primary")).not.toBeInTheDocument();
  expect(screen.queryByText("realtime")).not.toBeInTheDocument();
  expect(screen.getAllByRole("time")).toHaveLength(5);
  expect(
    screen.getByTitle(formatAdminLocalTimestamp("2026-09-17T03:00:00.000Z")),
  ).toBeVisible();
  expect(
    screen.queryByText(
      /Not registered|Registered|connection-primary|No telephony service registered/,
    ),
  ).not.toBeInTheDocument();
  expect(screen.queryByText(/secret-value/i)).not.toBeInTheDocument();
});

test("opens credential editing without revealing the stored secret", () => {
  render(<TenantServicesPage state={serviceFixture("populated")} />);

  fireEvent.click(
    screen.getByRole("button", { name: "Edit Google AI Studio credentials" }),
  );

  expect(screen.getByRole("dialog", { name: "Edit credential" })).toBeVisible();
  expect(screen.getByLabelText("Provider")).toHaveValue("google");
  expect(screen.queryByLabelText("Credential name")).not.toBeInTheDocument();
  expect(screen.getByLabelText("API key")).toHaveValue("");
  expect(
    screen.getByRole("button", { name: "Save" }),
  ).toBeVisible();
  expect(screen.queryByDisplayValue("****8c4a")).not.toBeInTheDocument();
});

test("opens and closes credential setup while restoring trigger focus", () => {
  render(<TenantServicesPage state={serviceFixture("populated")} />);
  const trigger = screen.getByRole("button", { name: "Connect a service" });

  fireEvent.click(trigger);
  expect(screen.getByRole("dialog", { name: "Connect a service" })).toBeVisible();
  expect(screen.getByLabelText("Provider")).toHaveFocus();
  screen.getByRole("button", { name: "Save" }).focus();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Tab" });
  expect(
    screen.getByRole("button", { name: "Close credential setup" }),
  ).toHaveFocus();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });

  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(trigger).toHaveFocus();
});

test("keeps empty and unavailable service inventories distinct", () => {
  const view = render(<TenantServicesPage state={serviceFixture("empty")} />);
  expect(screen.getByText("No services yet")).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect a service" })).toBeEnabled();

  view.rerender(<TenantServicesPage state={serviceFixture("unavailable")} />);
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Services could not be loaded",
  );
  expect(screen.getByRole("button", { name: "Connect a service" })).toBeDisabled();
});

test("keeps a bounded partial inventory usable and labels it truthfully", () => {
  render(
    <TenantServicesPage
      state={{ ...serviceFixture("populated"), truncated: true }}
    />,
  );

  expect(screen.getByText(/partial inventory/i)).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect a service" })).toBeEnabled();
});

test("presents duplicate credentials as a conflict without a replace action", () => {
  render(<TenantServicesPage state={serviceFixture("duplicate-conflict")} />);

  expect(screen.getByRole("alert", { name: "Notification" })).toHaveTextContent("already exists");
  expect(within(screen.getByRole("dialog")).getByRole("alert")).toHaveTextContent("already exists");
  expect(
    screen.queryByRole("button", { name: /replace|overwrite/i }),
  ).not.toBeInTheDocument();
});
