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
import { setupProvider, type SetupProviderId } from "./setupCatalog";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
  vi.useRealTimers();
});

function openConnected() {
  const category = screen.queryByRole("combobox", { name: "Category" });
  if (category) fireEvent.change(category, { target: { value: "connected" } });
}
function renderConnectedScenario(ui: ReactElement) {
  const view = render(ui);
  openConnected();
  return view;
}
function continueButton() {
  openConnected();
  return screen.getByRole("button", { name: "Continue" });
}
function serviceTrigger() {
  return within(screen.getByRole("navigation", { name: "Integration categories" })).getByRole("link", { name: /^AI models/ });
}

function openTenantDirectory() {
  fireEvent.click(screen.getByRole("button", { name: "Platform Integrations" }));
  fireEvent.click(screen.getByRole("button", { name: "Tenants" }));
}

function chooseDirectoryService(provider: string) {
  if (["telnyx", "twilio"].includes(provider))
    fireEvent.click(within(screen.getByRole("navigation", { name: "Integration categories" })).getByRole("link", { name: /Telephony/ }));
  fireEvent.click(screen.getByRole("button", { name: `Connect ${setupProvider(provider as SetupProviderId).name}` }));
}
function selectService(provider: string) {
  fireEvent.click(serviceTrigger());
  chooseDirectoryService(provider);
}

function serviceButtons() {
  openConnected();
  return ["AI services", "Telephony"].flatMap(name => within(screen.getByRole("region", { name })).queryAllByRole("button"))
    .map(button => button.getAttribute("aria-label") ?? button.textContent);
}

test("one service list connects Telnyx and Deepgram from the same picker", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);

  expect(screen.queryByRole("heading", { name: "AI providers" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Telephony" })).toBeVisible();
  expect(screen.getByRole("navigation", { name: "Integration categories" })).toBeVisible();

  for (const provider of ["telnyx", "deepgram"]) {
    fireEvent.click(serviceTrigger());
    chooseDirectoryService(provider);
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: `storybook-${provider}-key` },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    act(() => vi.advanceTimersByTime(1000));
  }

  expect(screen.getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
  expect(screen.getAllByRole("article", { name: "Deepgram" })).toHaveLength(1);
  expect(within(screen.getByRole("article", { name: "Telnyx" })).getByText("Telephony")).toBeVisible();
  expect(within(screen.getByRole("article", { name: "Deepgram" })).getByText("Speech-to-text")).toBeVisible();
});

test("all tenants share service copy and three explicit steps without samples on services", () => {
  const view = renderConnectedScenario(
    <OnboardingStory scenario="choose-services" theme="dark" />,
  );
  expect(screen.getByText("Tenant created: Demo")).toBeVisible();
  expect(
    within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText(
      "Integrations",
    ),
  ).toBeVisible();
  const steps = within(
    screen.getByRole("navigation", { name: "Tenant setup" }),
  );
  expect(
    steps.getAllByRole("button").map((button) => button.textContent),
  ).toEqual(["1Setup services", "2Create API Keys", "3Setup Call Specs"]);
  expect(screen.queryByText(/sample/i)).not.toBeInTheDocument();
  view.unmount();
  renderConnectedScenario(<OnboardingStory scenario="new-tenant-setup" theme="dark" />);
  expect(screen.getByText("Tenant created: Customer Care")).toBeVisible();
});

test.each(["Create & Join Calls", "Full Access"])(
  "creates a %s key and forgets the secret on navigation",
  (label) => {
    vi.useFakeTimers();
    renderConnectedScenario(<OnboardingStory scenario="api-keys" theme="dark" />);
    fireEvent.click(screen.getByRole("radio", { name: label }));
    fireEvent.change(screen.getByLabelText("Key name"), {
      target: { value: "My backend" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create API key" }));
    expect(
      screen.getByRole("button", { name: "Creating key…" }),
    ).toBeDisabled();
    act(() => vi.advanceTimersByTime(1000));
    const result = screen.getByRole("region", { name: "API key created" });
    expect(within(result).getByText("My backend")).toBeVisible();
    expect(within(result).getByText(label, { exact: true })).toBeVisible();
    expect(
      within(result).queryByText("admin", { exact: true }),
    ).not.toBeInTheDocument();
    expect(
      (screen.getByLabelText("API key") as HTMLInputElement).value,
    ).toContain("storybook-only");
    fireEvent.click(
      screen.getByRole("button", { name: "3Setup Call Specs" }),
    );
    expect(
      screen.getByRole("heading", { name: "Setup Call Specs" }),
    ).toBeVisible();
    expect(
      screen.getByRole("heading", { name: "Load sample call specs" }),
    ).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "2Create API Keys" }));
    expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
    expect(screen.getByText("My backend")).toBeVisible();
    fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
    fireEvent.click(screen.getByRole("link", { name: "New tenant" }));
    fireEvent.change(screen.getByLabelText("Tenant name"), {
      target: { value: "Another tenant" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
    act(() => vi.advanceTimersByTime(1000));
    fireEvent.click(screen.getByRole("button", { name: "2Create API Keys" }));
    expect(screen.queryByText("My backend")).not.toBeInTheDocument();
  },
);

test("empty integrations open connected rows, and credentials return focus on dismissal", () => {
  render(<OnboardingStory scenario="choose-services" theme="dark" />);
  expect(screen.getByRole("heading", { name: "Integrations", level: 1 })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
  fireEvent.click(serviceTrigger());
  const providerTrigger = screen.getByRole("button", { name: "Connect Deepgram" });
  fireEvent.click(providerTrigger);
  const dialog = screen.getByRole("dialog", { name: "Connect Deepgram" });
  expect(within(dialog).getByLabelText("API key")).toHaveFocus();
  fireEvent.keyDown(dialog, { key: "Escape" });
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(providerTrigger).toHaveFocus();
  openConnected();
  expect(screen.getByText("No AI integrations connected.")).toBeVisible();
  expect(continueButton()).toBeDisabled();
});

test("one speech provider covers two capabilities and a model provider unlocks samples", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);

  selectService("deepgram");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(screen.getByRole("dialog")).toHaveTextContent(
    "Saving credentials",
  );
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(continueButton()).toBeDisabled();

  selectService("google");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(continueButton()).toBeEnabled();
  fireEvent.click(continueButton());
  expect(
    screen.getByRole("heading", { name: "API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "3Setup Call Specs" }),
  );
  expect(
    screen.getByRole("heading", { name: "Setup Call Specs" }),
  ).toBeVisible();
  expect(screen.getAllByRole("button", { name: /^Load / })).toHaveLength(3);
  for (const button of screen.getAllByRole("button", { name: /^Load / }))
    expect(button).toBeEnabled();
  expect(
    screen.queryByRole("button", { name: /^Back to/ }),
  ).not.toBeInTheDocument();
  const navigation = screen.getByRole("navigation", { name: "Tenant setup" });
  fireEvent.click(
    within(navigation).getByRole("button", { name: /Create API Keys/ }),
  );
  expect(screen.getByRole("heading", { name: "API Keys" })).toBeVisible();
  expect(
    screen.queryByRole("button", { name: /^Back to/ }),
  ).not.toBeInTheDocument();
  fireEvent.click(
    within(navigation).getByRole("button", { name: /Setup services/ }),
  );
  expect(continueButton()).toBeEnabled();
});

test("blocked recipes remain readable and name the missing capability", () => {
  renderConnectedScenario(<OnboardingStory scenario="blocked-samples" theme="dark" />);
  expect(screen.getByRole("heading", { name: "Agent handoff" })).toBeVisible();
  expect(
    screen.getByText("Connect an LLM provider to try these samples."),
  ).toBeVisible();
  for (const button of screen.getAllByRole("button", { name: /^Load / }))
    expect(button).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Set up services" }));
  expect(continueButton()).toBeDisabled();
});

test("the supported default model reaches the chosen recipe", () => {
  renderConnectedScenario(<OnboardingStory scenario="multiple-providers" theme="light" />);
  fireEvent.click(continueButton());
  expect(
    screen.getByRole("heading", { name: "API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "3Setup Call Specs" }),
  );
  expect(
    screen.queryByRole("combobox", { name: "Language model provider" }),
  ).not.toBeInTheDocument();
  expect(screen.getByText("gemini-2.5-flash")).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Load Voice conversation" }),
  );
  expect(
    screen.getByRole("dialog", { name: "Voice conversation" }),
  ).toHaveTextContent("Google AI Studio");
});

test("the directory resumes setup without a redundant demo card", () => {
  const view = renderConnectedScenario(<OnboardingStory scenario="demo-nudge" theme="dark" />);
  fireEvent.click(screen.getByRole("link", { name: "Open Demo" }));
  openConnected();
  expect(screen.getByText("Tenant created: Demo")).toBeVisible();
  view.unmount();

  renderConnectedScenario(<OnboardingStory scenario="multiple-tenants" theme="dark" />);
  fireEvent.click(screen.getByRole("link", { name: "Open Acme Support" }));
  openConnected();
  expect(screen.getByText("Tenant created: Acme Support")).toBeVisible();
  expect(continueButton()).toBeDisabled();
});

test("returning through the tenant directory preserves completed service setup", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("deepgram");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  openTenantDirectory();
  fireEvent.click(screen.getByRole("link", { name: "Open Demo" }));
  openConnected();
  expect(continueButton()).toBeDisabled();
});

test("updating a speech service preserves the sample model provider", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="multiple-providers" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Rime" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  fireEvent.click(continueButton());
  expect(
    screen.getByRole("heading", { name: "API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "3Setup Call Specs" }),
  );
  expect(screen.getByText("Google AI Studio")).toBeVisible();
  expect(screen.getByText("gemini-2.5-flash")).toBeVisible();
});

test("the tenant directory opens a services-ready tenant before continuing to API keys", () => {
  renderConnectedScenario(<OnboardingStory scenario="ready-for-samples" theme="dark" />);
  openTenantDirectory();
  fireEvent.click(screen.getByRole("link", { name: "Open Demo" }));
  openConnected();
  fireEvent.click(continueButton());
  expect(
    screen.getByRole("heading", { name: "API Keys" }),
  ).toBeVisible();
});

test("creating a tenant asks only for a name and opens its own empty service setup", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="multiple-tenants" theme="dark" />);
  fireEvent.click(screen.getByRole("link", { name: "New tenant" }));
  const dialog = screen.getByRole("dialog", { name: "New tenant" });
  expect(within(dialog).getAllByRole("textbox")).toHaveLength(1);
  expect(within(dialog).getByLabelText("Tenant name")).toHaveFocus();
  fireEvent.change(screen.getByLabelText("Tenant name"), {
    target: { value: "  Customer Care  " },
  });
  fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
  expect(screen.getByRole("button", { name: "Creating…" })).toBeDisabled();
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByText("Tenant created: Customer Care")).toBeVisible();
  expect(continueButton()).toBeDisabled();
  expect(serviceTrigger()).toBeVisible();

  selectService("deepgram");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  openTenantDirectory();
  fireEvent.click(screen.getByRole("link", { name: "Open Customer Care" }));
  openConnected();
  expect(continueButton()).toBeDisabled();
  openTenantDirectory();
  fireEvent.click(screen.getByRole("link", { name: "Open Demo" }));
  openConnected();
  expect(continueButton()).toBeDisabled();
});

test("a blank tenant name cannot create a workspace, and cancel preserves the directory", () => {
  renderConnectedScenario(<OnboardingStory scenario="demo-nudge" theme="light" />);
  fireEvent.click(screen.getByRole("link", { name: "New tenant" }));
  expect(screen.getByRole("button", { name: "Create tenant" })).toBeDisabled();
  fireEvent.change(screen.getByLabelText("Tenant name"), {
    target: { value: "   " },
  });
  expect(screen.getByRole("button", { name: "Create tenant" })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("region", { name: "Continue demo setup" }),
  ).not.toBeInTheDocument();
});

test("the service picker clears drafts and keeps one connect action after saving", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="light" />);
  expect(serviceTrigger()).toBeVisible();
  expect(
    screen.queryByRole("region", { name: "Voice capabilities" }),
  ).not.toBeInTheDocument();
  expect(screen.queryByText("Connect a provider")).not.toBeInTheDocument();
  expect(screen.queryByText("Speak the response")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: "Connect Rime" }),
  ).not.toBeInTheDocument();
  const trigger = serviceTrigger();
  trigger.focus();
  fireEvent.click(trigger);
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  chooseDirectoryService("rime");
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "discard-this-draft" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  chooseDirectoryService("google");
  expect(screen.getByLabelText("API key")).toHaveValue("");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  chooseDirectoryService("rime");
  expect(screen.getByLabelText("API key")).toHaveValue("");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByRole("region", { name: "AI services" })).toHaveTextContent("Rime");
  expect(serviceButtons()).toEqual([
    "Manage Rime",
    "More actions for Rime",
  ]);
  expect(serviceTrigger()).toBeVisible();
  expect(continueButton()).toBeDisabled();
});

test("telephony remains optional and does not complete voice readiness", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="light" />);
  expect(serviceButtons()).toEqual([]);
  selectService("telnyx");
  expect(screen.getByLabelText("Public key")).toBeVisible();
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.change(screen.getByLabelText("Public key"), {
    target: { value: btoa("p".repeat(32)) },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(serviceButtons()).toEqual([
    "Manage Telnyx",
    "More actions for Telnyx",
  ]);
  expect(continueButton()).toBeDisabled();
});

test("connected providers share one service list and one connect action", () => {
  renderConnectedScenario(<OnboardingStory scenario="multiple-providers" theme="light" />);
  expect(serviceButtons()).toEqual([
    "Manage Deepgram",
    "More actions for Deepgram",
    "Manage Rime",
    "More actions for Rime",
    "Manage Google AI Studio",
    "More actions for Google AI Studio",
  ]);
});

test("connected cards separate connection status from the Manage action", () => {
  renderConnectedScenario(<OnboardingStory scenario="multiple-providers" theme="dark" />);
  const card = screen.getByRole("article", { name: "Deepgram" });
  expect(within(card).getByText("Connected")).toBeVisible();
  expect(within(card).getByText("Speech-to-text")).toBeVisible();
  expect(within(card).getByText("Text-to-speech")).toBeVisible();
  fireEvent.click(
    within(card).getByRole("button", { name: "Manage Deepgram" }),
  );
  expect(screen.getByRole("dialog", { name: "Manage Deepgram" })).toBeVisible();
});

test("the service card groups Edit and the credential-removal menu", () => {
  renderConnectedScenario(<OnboardingStory scenario="multiple-providers" theme="dark" />);
  const card = screen.getByRole("article", { name: "Deepgram" });
  const actions = within(card).getByRole("group", { name: "Deepgram actions" });

  expect(within(actions).getByRole("button", { name: "Manage Deepgram" })).toBeVisible();
  fireEvent.click(
    within(actions).getByRole("button", { name: "More actions for Deepgram" }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Remove credentials" }));

  expect(screen.queryByRole("article", { name: "Deepgram" })).not.toBeInTheDocument();
  expect(screen.queryByRole("dialog", { name: "Manage Deepgram" })).not.toBeInTheDocument();
});

test.each([["google", "Google AI Studio"]])(
  "%s shows capabilities on listings without repeating them in the credential modal",
  (provider, name) => {
    vi.useFakeTimers();
    renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);
    fireEvent.click(serviceTrigger());
    const listing = screen.getByRole("heading", { name, level: 3 }).closest("article")!;
    expect(within(listing).getByText("LLM")).toBeVisible();
    expect(within(listing).getByText("Speech-to-text")).toBeVisible();
    expect(within(listing).getByText("Text-to-speech")).toBeVisible();
    chooseDirectoryService(provider);
    const dialog = screen.getByRole("dialog", { name: `Connect ${name}` });
    expect(within(dialog).queryByText("LLM")).not.toBeInTheDocument();
    expect(within(dialog).queryByText("Speech-to-text")).not.toBeInTheDocument();
    expect(within(dialog).queryByText("Text-to-speech")).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "storybook-example-key" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    act(() => vi.advanceTimersByTime(1000));
    const card = screen.getByRole("article", { name });
    expect(within(card).getByText("LLM")).toBeVisible();
    expect(within(card).getByText("Speech-to-text")).toBeVisible();
    expect(within(card).getByText("Text-to-speech")).toBeVisible();
    expect(continueButton()).toBeEnabled();
  },
);

test("Rime connects with an API key in the shared service list", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("rime");
  expect(
    screen.getByRole("dialog", { name: "Connect Rime" }),
  ).not.toHaveTextContent("Text-to-speech");
  expect(
    screen
      .getByRole("form", { name: "Credential setup" })
      .querySelectorAll("input"),
  ).toHaveLength(1);
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-rime-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.getByRole("button", { name: "Manage Rime" })).toBeVisible();
  expect(within(screen.getByRole("article", { name: "Rime" })).getByText("Text-to-speech")).toBeVisible();
  expect(screen.queryByText("Credentials only")).not.toBeInTheDocument();
});

test("Telnyx is one service connection", () => {
  vi.useFakeTimers();
  renderConnectedScenario(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("telnyx");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-telnyx-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(within(screen.getByRole("article", { name: "Telnyx" })).getByText("Public key needed")).toBeVisible();
  for (let count = 0; count < 2; count++) {
    const region = screen.getByRole("region", { name: "Telephony" });
    expect(within(region).getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
    fireEvent.click(within(region).getByRole("button", { name: "Manage Telnyx" }));
    expect(screen.getByLabelText("API key")).toHaveValue("");
    expect(screen.getByLabelText("Public key")).toHaveValue("");
    expect(screen.queryByRole("combobox", { name: "Service" })).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "updated-storybook-key" },
    });
    if (count === 0) {
      fireEvent.change(screen.getByLabelText("Public key"), {
        target: { value: btoa("q".repeat(32)) },
      });
    }
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    act(() => vi.advanceTimersByTime(1000));
  }
  expect(screen.getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
  expect(screen.queryByText("Public key needed")).not.toBeInTheDocument();
  expect(screen.getAllByText("Connected")).toHaveLength(1);
});

test("the directory offers installed AI services and telephony in separate groups", () => {
  render(<OnboardingStory scenario="service-picker" theme="dark" />);
  expect(screen.getAllByRole("button", { name: /^Connect / }).map(button => button.textContent).filter(text => text === "Connect")).toHaveLength(11);
  expect(screen.getByRole("button", { name: "Connect Deepgram" })).toBeVisible();
  fireEvent.click(within(screen.getByRole("navigation", { name: "Integration categories" })).getByRole("link", { name: /Telephony/ }));
  expect(screen.getByRole("button", { name: "Connect Telnyx" })).toBeVisible();
  expect(screen.getByRole("button", { name: "Connect Twilio" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect Deepgram" })).not.toBeInTheDocument();
});

test("directory selection opens credentials and cancellation returns to browsing", () => {
  render(<OnboardingStory scenario="service-picker" theme="dark" />);
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  chooseDirectoryService("deepgram");
  expect(screen.getByLabelText("API key")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Integrations" })).toBeVisible();
});

test("returning from the directory shows the connected inventory", () => {
  render(<OnboardingStory scenario="service-picker" theme="dark" />);
  openConnected();
  expect(screen.getByText("No AI integrations connected.")).toBeVisible();
  fireEvent.click(serviceTrigger());
  expect(screen.getByRole("heading", { name: "Integrations" })).toBeVisible();
});
