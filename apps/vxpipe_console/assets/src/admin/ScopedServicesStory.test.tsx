import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { OnboardingStory } from "./OnboardingStory";

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

function manageTelnyx() {
  fireEvent.click(
    within(screen.getByRole("region", { name: "Telephony" })).getByRole(
      "button",
      { name: "Manage Telnyx" },
    ),
  );
}
function saveKey() {
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-dummy-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  act(() => vi.advanceTimersByTime(1000));
}

test("tenant connect and edit display an encoded tenant webhook using the supplied application origin", () => {
  const view = render(
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
  render(
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
  render(
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
    screen.getByRole("heading", { name: "Platform services", level: 1 }),
  ).toBeVisible();
  manageTelnyx();
  expect(screen.getByRole("dialog", { name: "Manage Telnyx" })).toBeVisible();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/platform/telnyx",
  );
});

test("inherited services count toward readiness and Telnyx overrides use an independent public key", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="inherited-services" theme="dark" />);
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
  const telephony = within(screen.getByRole("region", { name: "Telephony" }));
  expect(telephony.getByText("Tenant override")).toBeVisible();
  expect(telephony.getByText("Public key needed")).toBeVisible();
  manageTelnyx();
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(telephony.getByText("Inherited from platform")).toBeVisible();
  expect(telephony.getByText("Connected")).toBeVisible();
});

test("disabling an inherited service blocks readiness and can be reversed without credentials", () => {
  render(<OnboardingStory scenario="inherited-services" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  fireEvent.click(
    screen.getByRole("button", { name: "Disable for this tenant" }),
  );
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
  expect(screen.getByText("Disabled for this tenant")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(screen.getByRole("button", { name: "Continue" })).toBeEnabled();
});

test("a failed tenant override never uses platform readiness", () => {
  render(<OnboardingStory scenario="tenant-override-error" theme="dark" />);
  expect(screen.getByText("Credentials need attention")).toBeVisible();
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("platform saves become available to a newly created tenant", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="platform-services" theme="dark" />);
  fireEvent.click(
    within(screen.getByRole("region", { name: "AI providers" })).getAllByRole(
      "button",
      { name: "Connect a service" },
    )[0],
  );
  fireEvent.change(screen.getByLabelText("Service"), {
    target: { value: "deepgram" },
  });
  saveKey();
  fireEvent.click(screen.getByRole("button", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("button", { name: "New tenant" }));
  fireEvent.change(screen.getByLabelText("Tenant name"), {
    target: { value: "New team" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.getByText("Inherited from platform")).toBeVisible();
  expect(screen.getByRole("button", { name: "Manage Deepgram" })).toBeVisible();
});

test("webhook copy gives success and usable failure feedback", async () => {
  const writeText = vi.fn().mockResolvedValue(undefined);
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  render(<OnboardingStory scenario="telnyx-credentials" theme="dark" />);
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
