import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import type { ReactElement } from "react";
import { OnboardingStory } from "./OnboardingStory";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
  vi.useRealTimers();
  vi.restoreAllMocks();
});

function openConnected() {
  const category = screen.queryByRole("combobox", { name: "Category" });
  if (category) fireEvent.change(category, { target: { value: "connected" } });
}
function renderConnected(ui: ReactElement) { const view = render(ui); openConnected(); return view; }
function manageTelnyx() {
  fireEvent.click(screen.getByRole("button", { name: "Manage Telnyx" }));
}
function saveKey() {
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-dummy-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  openConnected();
}

test("tenant connect and edit display an encoded tenant webhook using the supplied application origin", () => {
  const view = renderConnected(
    <OnboardingStory
      scenario="telnyx-credentials"
      theme="dark"
      publicOrigin="http://localhost:4567"
    />,
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4567/webhooks/tenants/demo-tenant/telnyx",
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveAttribute("readonly");
  fireEvent.click(screen.getByRole("button", { name: "Close dialog" }));
  view.unmount();
  renderConnected(
    <OnboardingStory
      scenario="telnyx-connected"
      theme="dark"
      publicOrigin="https://voice.example.test"
    />,
  );
  manageTelnyx();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "https://voice.example.test/webhooks/tenants/demo-tenant/telnyx",
  );
});

test("platform connect and edit display the platform webhook without tenant steps", () => {
  vi.useFakeTimers();
  renderConnected(
    <OnboardingStory
      scenario="platform-telnyx"
      theme="dark"
      publicOrigin="http://localhost:4000"
    />,
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/platform/telnyx",
  );
  expect(
    screen.queryByRole("navigation", { name: "Tenant setup" }),
  ).not.toBeInTheDocument();
  saveKey();
  expect(
    screen.getByRole("heading", { name: "Platform Integrations", level: 1 }),
  ).toBeVisible();
  manageTelnyx();
  expect(screen.getByRole("dialog", { name: "Manage Telnyx" })).toBeVisible();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/platform/telnyx",
  );
});

test("inherited services count toward readiness and Telnyx overrides use an independent public key", () => {
  vi.useFakeTimers();
  renderConnected(<OnboardingStory scenario="inherited-services" theme="dark" />);
  expect(screen.getByRole("button", { name: "Continue" })).toBeEnabled();
  manageTelnyx();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/platform/telnyx",
  );
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Override for this tenant" }),
  );
  expect(screen.getByLabelText("API key")).toHaveFocus();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/tenants/demo-tenant/telnyx",
  );
  saveKey();
  const telephony = within(screen.getByRole("article", { name: "Telnyx" }));
  expect(telephony.getByText("Tenant override")).toBeVisible();
  expect(telephony.getByText("Public key needed")).toBeVisible();
  manageTelnyx();
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(telephony.queryByText("Inherited from platform")).not.toBeInTheDocument();
  expect(telephony.getByText("Connected")).toBeVisible();
});

test("inherited services have no disable or remove control", () => {
  renderConnected(<OnboardingStory scenario="inherited-services" theme="dark" />);
  const card = screen.getByRole("article", { name: "Deepgram" });
  expect(
    within(card).queryByRole("button", { name: "More actions for Deepgram" }),
  ).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  expect(
    screen.queryByRole("button", { name: /Disable|Remove service/ }),
  ).not.toBeInTheDocument();
  expect(
    screen.getByRole("button", { name: "Override for this tenant" }),
  ).toBeVisible();
});

test("a failed tenant override never uses platform readiness", () => {
  renderConnected(<OnboardingStory scenario="tenant-override-error" theme="dark" />);
  expect(screen.getByLabelText("Credentials need attention")).toBeVisible();
  expect(screen.queryByText("Credentials need attention")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("platform saves become available to a newly created tenant", () => {
  vi.useFakeTimers();
  renderConnected(<OnboardingStory scenario="platform-services" theme="dark" />);
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect Deepgram" }));
  saveKey();
  fireEvent.click(screen.getByRole("button", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("link", { name: "New tenant" }));
  fireEvent.change(screen.getByLabelText("Tenant name"), {
    target: { value: "New team" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  act(() => vi.advanceTimersByTime(1000));
  openConnected();
  expect(screen.queryByText("Inherited from platform")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Manage Deepgram" })).toBeVisible();
});

test("webhook copy gives success and usable failure feedback", async () => {
  const writeText = vi.fn().mockResolvedValue(undefined);
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  renderConnected(<OnboardingStory scenario="telnyx-credentials" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Copy webhook URL" }));
  expect(await screen.findByText("Webhook URL copied.")).toBeVisible();
  expect(writeText).toHaveBeenCalledWith(
    "http://localhost:4000/webhooks/tenants/demo-tenant/telnyx",
  );
  writeText.mockRejectedValueOnce(new Error("denied"));
  fireEvent.click(screen.getByRole("button", { name: "Copy webhook URL" }));
  expect(
    await screen.findByText(
      "Copy failed. Select the URL and copy it manually.",
    ),
  ).toBeVisible();
});
