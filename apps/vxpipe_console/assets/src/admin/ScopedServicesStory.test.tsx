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
  const publicKey = screen.queryByLabelText("Public key");
  if (publicKey) fireEvent.change(publicKey, { target: { value: btoa("q".repeat(32)) } });
  const application = screen.queryByLabelText("Voice API application ID") as HTMLInputElement | null;
  if (application && !application.value) fireEvent.change(application, { target: { value: "tenant-application" } });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-dummy-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  openConnected();
}

test("an inherited Telnyx connection saves a tenant application without overriding credentials", () => {
  renderConnected(<OnboardingStory scenario="inherited-services" theme="dark" />);
  manageTelnyx();
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Service name")).not.toBeInTheDocument();
  expect(screen.queryByText("Phone routing")).not.toBeInTheDocument();
  expect(screen.queryByLabelText(/Outbound caller/)).not.toBeInTheDocument();
  expect(screen.getByLabelText("Voice API application ID")).toHaveAttribute("readonly");
  fireEvent.click(screen.getByRole("button", { name: "Override voice application" }));
  fireEvent.change(screen.getByLabelText("Voice API application ID"), {
    target: { value: "2912345678901234568" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234568");
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx");
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "unsaved" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234568");
});

test("Telnyx credential override clears the application and validates its replacement", () => {
  renderConnected(<OnboardingStory scenario="inherited-services" theme="dark" />);
  manageTelnyx();
  fireEvent.click(screen.getByRole("button", { name: "Override voice application" }));
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(screen.getByRole("alert")).toHaveTextContent("Voice API application ID");
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "2912345678901234568" } });
  fireEvent.click(screen.getByRole("button", { name: "Override credentials" }));
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("");
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx");
  expect(screen.getByLabelText("API key")).toHaveValue("");
});

test("a saved tenant connection can change its application without replacing credentials", () => {
  renderConnected(<OnboardingStory scenario="telnyx-override" theme="dark" />);
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "2912345678901234568" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234568");
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234568");
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx");
});

test("tenant connect and edit display an encoded tenant webhook using the supplied application origin", () => {
  const view = renderConnected(
    <OnboardingStory
      scenario="telnyx-credentials"
      theme="dark"
      publicOrigin="http://localhost:4567"
    />,
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4567/webhooks/tenants/DemoTenant000001/telnyx",
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
    "https://voice.example.test/webhooks/tenants/DemoTenant000001/telnyx",
  );
});

test("platform connect saves the shared application and platform webhook", () => {
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
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "2912345678901234567" } });
  expect(
    screen.queryByRole("navigation", { name: "Tenant setup" }),
  ).not.toBeInTheDocument();
  saveKey();
  expect(
    screen.getByRole("heading", { name: "Platform Integrations", level: 1 }),
  ).toBeVisible();
  manageTelnyx();
  expect(screen.getByRole("dialog", { name: "Telnyx" })).toBeVisible();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234567");
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
    screen.getByRole("button", { name: "Override credentials" }),
  );
  expect(screen.getByLabelText("API key")).toHaveFocus();
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx",
  );
  saveKey();
  const telephony = within(screen.getByRole("article", { name: "Telnyx" }));
  expect(telephony.getByText("Tenant override")).toBeVisible();
  expect(telephony.queryByText("Public key needed")).not.toBeInTheDocument();
  manageTelnyx();
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
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

test("webhook copy briefly confirms in the button and retains usable failure feedback", async () => {
  vi.useFakeTimers();
  const writeText = vi.fn().mockResolvedValue(undefined);
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  renderConnected(<OnboardingStory scenario="telnyx-credentials" theme="dark" />);
  const button = screen.getByRole("button", { name: "Copy webhook URL" });
  await act(async () => fireEvent.click(button));
  expect(button).toHaveTextContent("Copied");
  expect(screen.queryByText("Webhook URL copied.")).not.toBeInTheDocument();
  expect(writeText).toHaveBeenCalledWith(
    "http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx",
  );
  act(() => vi.advanceTimersByTime(2000));
  expect(button).toHaveTextContent("Copy");
  expect(button).not.toHaveTextContent("Copied");
  writeText.mockRejectedValueOnce(new Error("denied"));
  await act(async () => fireEvent.click(button));
  expect(
    screen.getByText(
      "Copy failed. Select the URL and copy it manually.",
    ),
  ).toBeVisible();
});

test("credential override requires a tenant application and Cancel discards changes", () => {
  renderConnected(<OnboardingStory scenario="telnyx-inherited" theme="dark" />);
  const application = screen.getByLabelText("Voice API application ID");
  expect(application).toHaveValue("2912345678901234567");
  expect(application).toHaveAttribute("readonly");
  expect(screen.queryByText(/Local preview/)).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Override credentials" }));
  expect(screen.getByLabelText("API key")).toHaveFocus();
  expect(application).not.toHaveAttribute("readonly");
  expect(application).toHaveValue("");
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx");
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for voice application" }));
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/platform/telnyx");
  fireEvent.click(screen.getByRole("button", { name: "Override voice application" }));
  fireEvent.change(application, { target: { value: "tenant-app" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("2912345678901234567");
  expect(screen.getByLabelText("Voice API application ID")).toHaveAttribute("readonly");
});

test("restoring the shared application requires restoring platform credentials first", () => {
  renderConnected(<OnboardingStory scenario="telnyx-override" theme="dark" />);
  expect(screen.queryByRole("button", { name: "Use platform default for voice application" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for voice application" }));
  expect(screen.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/platform/telnyx");
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  manageTelnyx();
  expect(screen.getByLabelText("Voice API application ID")).toHaveAttribute("readonly");
  expect(screen.getByRole("button", { name: "Override credentials" })).toBeVisible();
});


test("the voice application contains its webhook and an application override switches its URL", () => {
  renderConnected(<OnboardingStory scenario="telnyx-inherited" theme="dark" />);
  const voice = within(screen.getByRole("region", { name: "Voice application" }));
  expect(voice.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/platform/telnyx");
  fireEvent.click(voice.getByRole("button", { name: "Override voice application" }));
  expect(voice.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/tenants/DemoTenant000001/telnyx");
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(screen.queryByText(/Tenant webhook|Update the webhook in Telnyx/)).not.toBeInTheDocument();
  fireEvent.click(voice.getByRole("button", { name: "Use platform default for voice application" }));
  expect(voice.getByLabelText("Webhook URL")).toHaveValue("http://localhost:4000/webhooks/platform/telnyx");
});
