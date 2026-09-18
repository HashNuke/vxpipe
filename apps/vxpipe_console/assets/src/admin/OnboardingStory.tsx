import { useState } from "react";

import { OnboardingPage } from "./OnboardingPage";
import {
  onboardingProvider,
  onboardingSamples,
  readyOnboardingState,
} from "./onboardingFixtures";
import type { OnboardingPageState } from "./onboardingTypes";
import type { CredentialDraft, ServiceProvider } from "./serviceTypes";

export type OnboardingScenario =
  | "creating-tenant"
  | "choose-services"
  | "enter-credentials"
  | "validating"
  | "validation-error"
  | "ready-for-samples"
  | "loading-samples"
  | "complete"
  | "unavailable";

export function OnboardingStory({
  scenario,
  theme,
}: {
  scenario: OnboardingScenario;
  theme: "dark" | "light";
}) {
  const [state, setState] = useState(() => stateForScenario(scenario));

  function selectProviders(providers: ServiceProvider[]) {
    setState((current) => ({
      ...current,
      providers: providers.flatMap((provider) =>
        provider === "vertex_ai" ? [] : [onboardingProvider(provider, "needs_credentials")],
      ),
      samples: { status: "blocked", items: onboardingSamples },
    }));
  }

  function submitCredential(draft: CredentialDraft) {
    setState((current) => {
      const providers = current.providers.map((provider) =>
        provider.provider === draft.provider
          ? { ...provider, status: "valid" as const, lastValidatedAt: new Date().toISOString() }
          : provider,
      );

      return {
        ...current,
        providers,
        samples: {
          ...current.samples,
          status: providers.every((provider) => provider.status === "valid")
            ? "ready"
            : "blocked",
        },
      };
    });
  }

  function installSamples() {
    setState((current) => ({
      ...current,
      samples: {
        status: "complete",
        items: current.samples.items.map((sample) => ({ ...sample, status: "installed" })),
      },
    }));
  }

  return (
    <OnboardingPage
      onInstallSamples={installSamples}
      onSelectProviders={selectProviders}
      onSubmitCredential={submitCredential}
      state={state}
      theme={theme}
    />
  );
}

function stateForScenario(scenario: OnboardingScenario): OnboardingPageState {
  switch (scenario) {
    case "creating-tenant":
      return {
        tenant: { status: "creating", name: "DemoTenant" },
        providers: [],
        samples: { status: "blocked", items: [] },
      };
    case "choose-services":
      return {
        ...readyOnboardingState,
        providers: [],
        samples: { status: "blocked", items: onboardingSamples },
      };
    case "enter-credentials":
      return {
        ...readyOnboardingState,
        providers: [
          onboardingProvider("deepgram", "needs_credentials"),
          onboardingProvider("google", "needs_credentials"),
        ],
        samples: { status: "blocked", items: onboardingSamples },
      };
    case "validating":
      return {
        ...readyOnboardingState,
        providers: [
          onboardingProvider("deepgram", "valid", {
            lastValidatedAt: "2026-09-18T04:30:00Z",
          }),
          onboardingProvider("google", "validating"),
        ],
        samples: { status: "blocked", items: onboardingSamples },
      };
    case "validation-error":
      return {
        ...readyOnboardingState,
        providers: [
          onboardingProvider("deepgram", "valid", {
            lastValidatedAt: "2026-09-18T04:30:00Z",
          }),
          onboardingProvider("google", "invalid", {
            message: "Google rejected this API key. Check it and try again.",
          }),
        ],
        samples: { status: "blocked", items: onboardingSamples },
      };
    case "ready-for-samples":
      return readyOnboardingState;
    case "loading-samples":
      return {
        ...readyOnboardingState,
        samples: { status: "loading", items: onboardingSamples },
      };
    case "complete":
      return {
        ...readyOnboardingState,
        samples: {
          status: "complete",
          items: onboardingSamples.map((sample) => ({ ...sample, status: "installed" })),
        },
      };
    case "unavailable":
      return {
        tenant: {
          status: "unavailable",
          name: "DemoTenant",
          message: "The setup endpoint is unavailable. Retry after the Console reconnects.",
        },
        providers: [],
        samples: { status: "blocked", items: [] },
      };
  }
}
