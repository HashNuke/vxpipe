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
});

function serviceTrigger() {
  return screen.getByRole("button", { name: "Connect a service" });
}

function selectService(provider: string) {
  fireEvent.click(serviceTrigger());
  fireEvent.change(screen.getByRole("combobox", { name: "Service" }), {
    target: { value: provider },
  });
}

function serviceButtons() {
  return within(screen.getByRole("region", { name: "Setup services" }))
    .getAllByRole("button")
    .map((button) => button.getAttribute("aria-label") ?? button.textContent);
}

test("one service list connects Telnyx and Deepgram from the same picker", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="dark" />);

  expect(screen.queryByRole("heading", { name: "AI providers" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Telephony" })).not.toBeInTheDocument();
  expect(screen.getAllByRole("button", { name: "Connect a service" })).toHaveLength(1);

  for (const provider of ["telnyx", "deepgram"]) {
    fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
    const picker = screen.getByRole("combobox", { name: "Service" });
    expect(within(picker).getByRole("option", { name: "Telnyx" })).toBeVisible();
    expect(within(picker).getByRole("option", { name: "Deepgram" })).toBeVisible();
    fireEvent.change(picker, { target: { value: provider } });
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
  const view = render(
    <OnboardingStory scenario="choose-services" theme="dark" />,
  );
  expect(screen.getByText("Tenant created: Demo")).toBeVisible();
  expect(
    within(screen.getByRole("navigation", { name: "Breadcrumb" })).getByText(
      "Setup services",
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
  render(<OnboardingStory scenario="new-tenant-setup" theme="dark" />);
  expect(screen.getByText("Tenant created: Customer Care")).toBeVisible();
  expect(
    screen.getByText(
      "Connect services to get started. You can rename this tenant later.",
    ),
  ).toBeVisible();
});

test.each(["Create & Join Calls", "Full Access"])(
  "creates a %s key and forgets the secret on navigation",
  (label) => {
    vi.useFakeTimers();
    render(<OnboardingStory scenario="api-keys" theme="dark" />);
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
      screen.getByRole("button", { name: "Continue to Setup Call Specs" }),
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
    fireEvent.click(screen.getByRole("button", { name: "New tenant" }));
    fireEvent.change(screen.getByLabelText("Tenant name"), {
      target: { value: "Another tenant" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create tenant" }));
    act(() => vi.advanceTimersByTime(1000));
    fireEvent.click(screen.getByRole("button", { name: "2Create API Keys" }));
    expect(screen.queryByText("My backend")).not.toBeInTheDocument();
  },
);

test("empty services keep one connect action that opens the service picker", () => {
  render(<OnboardingStory scenario="choose-services" theme="dark" />);

  expect(screen.getByText("Tenant created: Demo")).toBeVisible();
  expect(
    screen.getByText(
      "Connect services to get started. You can rename this tenant later.",
    ),
  ).toBeVisible();
  expect(
    screen.getByRole("heading", { name: "Setup services", level: 1 }),
  ).toBeVisible();
  expect(screen.queryByRole("heading", { name: "AI providers" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Telephony" })).not.toBeInTheDocument();
  expect(
    screen.queryByRole("heading", { name: "Tenant created: Demo" }),
  ).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("heading", { name: "Voice conversation" }),
  ).not.toBeInTheDocument();

  expect(
    screen.queryByText(
      "Connect Speech-to-speech, or Speech-to-text + LLM + Text-to-speech.",
    ),
  ).not.toBeInTheDocument();
  expect(serviceButtons()).toEqual(["Connect a service"]);
  const trigger = serviceTrigger();
  trigger.focus();
  fireEvent.click(trigger);
  const dialog = screen.getByRole("dialog", { name: "Connect a service" });
  const service = within(dialog).getByRole("combobox", { name: "Service" });
  expect(service).toHaveFocus();
  fireEvent.change(service, { target: { value: "deepgram" } });
  expect(within(dialog).getByLabelText("API key")).toHaveFocus();
  expect(
    screen.getByRole("button", { name: "Save" }),
  ).toBeEnabled();
  fireEvent.keyDown(dialog, { key: "Escape" });
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(trigger).toHaveFocus();
});

test("one speech provider covers two capabilities and a model provider unlocks samples", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="dark" />);

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
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();

  selectService("google");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.getByRole("button", { name: "Continue" })).toBeEnabled();
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(
    screen.getByRole("heading", { name: "Create API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Continue to Setup Call Specs" }),
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
  expect(screen.getByRole("heading", { name: "Create API Keys" })).toBeVisible();
  expect(
    screen.queryByRole("button", { name: /^Back to/ }),
  ).not.toBeInTheDocument();
  fireEvent.click(
    within(navigation).getByRole("button", { name: /Setup services/ }),
  );
  expect(screen.getByRole("button", { name: "Continue" })).toBeEnabled();
});

test("blocked recipes remain readable and name the missing capability", () => {
  render(<OnboardingStory scenario="blocked-samples" theme="dark" />);
  expect(screen.getByRole("heading", { name: "Agent handoff" })).toBeVisible();
  expect(
    screen.getByText("Connect an LLM provider to try these samples."),
  ).toBeVisible();
  for (const button of screen.getAllByRole("button", { name: /^Load / }))
    expect(button).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Set up services" }));
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("the supported default model reaches the chosen recipe", () => {
  render(<OnboardingStory scenario="multiple-providers" theme="light" />);
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(
    screen.getByRole("heading", { name: "Create API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Continue to Setup Call Specs" }),
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

test("the demo nudge resumes setup and another tenant retains its own name", () => {
  const view = render(<OnboardingStory scenario="demo-nudge" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Continue setup" }));
  expect(screen.getByText("Tenant created: Demo")).toBeVisible();
  view.unmount();

  render(<OnboardingStory scenario="multiple-tenants" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Set up Acme Support" }));
  expect(screen.getByText("Tenant created: Acme Support")).toBeVisible();
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("returning through the tenant directory preserves completed service setup", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("deepgram");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("button", { name: "Continue setup" }));
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("updating a speech service preserves the sample model provider", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="multiple-providers" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Rime" }));
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
  expect(
    screen.getByRole("heading", { name: "Create API Keys" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Continue to Setup Call Specs" }),
  );
  expect(screen.getByText("Google AI Studio")).toBeVisible();
  expect(screen.getByText("gemini-2.5-flash")).toBeVisible();
});

test("the tenant directory resumes a services-ready tenant at API keys", () => {
  render(<OnboardingStory scenario="ready-for-samples" theme="dark" />);
  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("button", { name: "Set up Demo" }));
  expect(
    screen.getByRole("heading", { name: "Create API Keys" }),
  ).toBeVisible();
});

test("creating a tenant asks only for a name and opens its own empty service setup", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="multiple-tenants" theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "New tenant" }));
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
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Connect a service" })).toBeVisible();

  selectService("deepgram");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("button", { name: "Set up Customer Care" }));
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
  fireEvent.click(screen.getByRole("link", { name: "Tenants" }));
  fireEvent.click(screen.getByRole("button", { name: "Set up Demo" }));
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("a blank tenant name cannot create a workspace, and cancel preserves the directory", () => {
  render(<OnboardingStory scenario="demo-nudge" theme="light" />);
  fireEvent.click(screen.getByRole("button", { name: "New tenant" }));
  expect(screen.getByRole("button", { name: "Create tenant" })).toBeDisabled();
  fireEvent.change(screen.getByLabelText("Tenant name"), {
    target: { value: "   " },
  });
  expect(screen.getByRole("button", { name: "Create tenant" })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(
    screen.getByRole("region", { name: "Continue demo setup" }),
  ).toBeVisible();
});

test("the service picker clears drafts and keeps one connect action after saving", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="light" />);
  expect(screen.getByRole("button", { name: "Connect a service" })).toBeVisible();
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
  const picker = screen.getByRole("dialog", { name: "Connect a service" });
  const service = within(picker).getByRole("combobox", { name: "Service" });
  expect(service).toHaveFocus();
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  fireEvent.change(service, { target: { value: "rime" } });
  expect(screen.getByRole("dialog", { name: "Connect Rime" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "discard-this-draft" },
  });
  expect(within(service).getByRole("option", { name: "Twilio" })).toBeVisible();
  fireEvent.change(service, { target: { value: "google" } });
  expect(screen.getByLabelText("API key")).toHaveValue("");
  fireEvent.change(service, { target: { value: "rime" } });
  expect(screen.getByLabelText("API key")).toHaveValue("");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByRole("region", { name: "Setup services" })).toHaveTextContent("Rime");
  expect(serviceButtons()).toEqual([
    "Connect a service",
    "Manage Rime",
    "More actions for Rime",
  ]);
  expect(trigger).toHaveFocus();
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("telephony remains optional and does not complete voice readiness", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="light" />);
  expect(serviceButtons()).toEqual(["Connect a service"]);
  selectService("telnyx");
  const service = screen.getByRole("combobox", { name: "Service" });
  expect(within(service).getByRole("option", { name: "Deepgram" })).toBeVisible();
  expect(screen.getByLabelText("Public key")).toBeVisible();
  fireEvent.change(service, { target: { value: "telnyx" } });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-example-key" },
  });
  fireEvent.change(screen.getByLabelText("Public key"), {
    target: { value: btoa("p".repeat(32)) },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(serviceButtons()).toEqual([
    "Connect a service",
    "Manage Telnyx",
    "More actions for Telnyx",
  ]);
  expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
});

test("connected providers share one service list and one connect action", () => {
  render(<OnboardingStory scenario="multiple-providers" theme="light" />);
  expect(serviceButtons()).toEqual([
    "Connect a service",
    "Manage Deepgram",
    "More actions for Deepgram",
    "Manage Rime",
    "More actions for Rime",
    "Manage Google AI Studio",
    "More actions for Google AI Studio",
  ]);
});

test("connected cards separate connection status from the Manage action", () => {
  render(<OnboardingStory scenario="multiple-providers" theme="dark" />);
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
  render(<OnboardingStory scenario="multiple-providers" theme="dark" />);
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
  "%s shows all installed speech and language capabilities",
  (provider, name) => {
    vi.useFakeTimers();
    render(<OnboardingStory scenario="choose-services" theme="dark" />);
    selectService(provider);
    const dialog = screen.getByRole("dialog", { name: `Connect ${name}` });
    expect(within(dialog).getByText("LLM")).toBeVisible();
    expect(within(dialog).getByText("Speech-to-text")).toBeVisible();
    expect(within(dialog).getByText("Text-to-speech")).toBeVisible();
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "storybook-example-key" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    act(() => vi.advanceTimersByTime(1000));
    const card = screen.getByRole("article", { name });
    expect(within(card).getByText("LLM")).toBeVisible();
    expect(within(card).getByText("Speech-to-text")).toBeVisible();
    expect(within(card).getByText("Text-to-speech")).toBeVisible();
    expect(screen.getByRole("button", { name: "Continue" })).toBeEnabled();
  },
);

test("Rime connects with an API key in the shared service list", () => {
  vi.useFakeTimers();
  render(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("rime");
  expect(
    screen.getByRole("dialog", { name: "Connect Rime" }),
  ).toHaveTextContent("Text-to-speech");
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
  render(<OnboardingStory scenario="choose-services" theme="dark" />);
  selectService("telnyx");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-telnyx-key" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  act(() => vi.advanceTimersByTime(1000));
  expect(within(screen.getByRole("article", { name: "Telnyx" })).getByText("Public key needed")).toBeVisible();
  for (let count = 0; count < 2; count++) {
    const region = screen.getByRole("region", { name: "Setup services" });
    expect(within(region).getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
    fireEvent.click(within(region).getByRole("button", { name: "Manage Telnyx" }));
    expect(screen.getByLabelText("API key")).toHaveValue("");
    expect(screen.getByLabelText("Public key")).toHaveValue("");
    const options = within(screen.getByRole("combobox", { name: "Service" }));
    expect(options.getByRole("option", { name: "Rime" })).toBeVisible();
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

test("onboarding offers only installed AI and telephony services in their groups", () => {
  render(<OnboardingStory scenario="service-picker" theme="dark" />);
  const service = screen.getByRole("combobox", { name: "Service" });
  expect(
    within(service)
      .getAllByRole("option")
      .map((option) => option.textContent),
  ).toEqual([
    "Select a service",
    "Deepgram",
    "Rime",
    "Cartesia",
    "ElevenLabs",
    "Google AI Studio",
    "OpenAI",
    "Zenmux",
    "DeepSeek",
    "OpenRouter",
    "Fireworks AI",
    "Telnyx",
    "Twilio",
  ]);
});
