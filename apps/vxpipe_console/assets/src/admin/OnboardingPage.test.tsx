import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { OnboardingPage } from "./OnboardingPage";
import type { OnboardingPageState } from "./onboardingTypes";

afterEach(cleanup);

const readyState: OnboardingPageState = {
  tenant: { status: "ready", key: "demo-tenant", name: "Demo" },
  providers: [
    {
      provider: "deepgram",
      label: "Deepgram",
      services: ["Speech to text", "Text to speech"],
      status: "valid",
      lastValidatedAt: "2026-09-18T04:30:00Z",
    },
    {
      provider: "google",
      label: "Google AI Studio",
      services: ["Language model"],
      status: "valid",
      lastValidatedAt: "2026-09-18T04:31:00Z",
    },
  ],
  samples: {
    status: "ready",
    items: [
      { id: "voice-conversation", name: "Voice conversation", status: "available" },
      { id: "agent-handoff", name: "Agent handoff", status: "available" },
      { id: "human-handoff", name: "Human handoff", status: "available" },
    ],
  },
};

test("shows automatic Demo creation as the first resumable step", () => {
  render(
    <OnboardingPage
      onInstallSamples={vi.fn()}
      onSelectProviders={vi.fn()}
      onSubmitCredential={vi.fn()}
      state={{ ...readyState, tenant: { status: "creating", name: "Demo" } }}
    />,
  );

  expect(screen.getByRole("heading", { name: "Preparing Demo" })).toBeVisible();
  expect(screen.getByText("Creating the first tenant for this installation…")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Load sample call specs" })).not.toBeInTheDocument();
});

test("shows which services each connected provider covers and when it was tested", () => {
  render(
    <OnboardingPage
      onInstallSamples={vi.fn()}
      onSelectProviders={vi.fn()}
      onSubmitCredential={vi.fn()}
      state={readyState}
    />,
  );

  expect(screen.getByRole("heading", { name: "Connect your services" })).toBeVisible();
  expect(screen.getByText("Speech to text")).toBeVisible();
  expect(screen.getByText("Text to speech")).toBeVisible();
  expect(screen.getByText("Language model")).toBeVisible();
  expect(screen.getAllByText(/Last tested /)).toHaveLength(2);
  expect(screen.getByRole("button", { name: "Load sample call specs" })).toBeEnabled();
});

test("submits provider selection and offers sample installation after validation", () => {
  const selectProviders = vi.fn();
  const installSamples = vi.fn();

  const selection = render(
    <OnboardingPage
      onInstallSamples={installSamples}
      onSelectProviders={selectProviders}
      onSubmitCredential={vi.fn()}
      state={{ ...readyState, providers: [], samples: { ...readyState.samples, status: "blocked" } }}
    />,
  );

  fireEvent.click(screen.getByRole("checkbox", { name: "Deepgram" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "Google AI Studio" }));
  fireEvent.click(screen.getByRole("button", { name: "Continue with 2 services" }));
  expect(selectProviders).toHaveBeenCalledWith(["deepgram", "google"]);

  selection.unmount();
  render(
    <OnboardingPage
      onInstallSamples={installSamples}
      onSelectProviders={selectProviders}
      onSubmitCredential={vi.fn()}
      state={readyState}
    />,
  );
  fireEvent.click(screen.getByRole("button", { name: "Load sample call specs" }));
  expect(installSamples).toHaveBeenCalledOnce();
});

test("keeps a failed provider actionable without claiming it was tested", () => {
  render(
    <OnboardingPage
      onInstallSamples={vi.fn()}
      onSelectProviders={vi.fn()}
      onSubmitCredential={vi.fn()}
      state={{
        ...readyState,
        providers: [
          {
            provider: "google",
            label: "Google AI Studio",
            services: ["Language model"],
            status: "invalid",
            message: "Google rejected this API key. Check it and try again.",
            lastValidatedAt: null,
          },
        ],
        samples: { ...readyState.samples, status: "blocked" },
      }}
    />,
  );

  expect(screen.getByRole("alert")).toHaveTextContent("Google rejected this API key");
  expect(screen.queryByText(/Last tested /)).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Load sample call specs" })).not.toBeInTheDocument();
});
