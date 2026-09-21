import type { OnboardingPageState, OnboardingProvider } from "./onboardingTypes";
import type { ServiceProvider } from "./serviceTypes";

export const onboardingSamples: OnboardingPageState["samples"]["items"] = [
  { id: "voice-conversation", name: "Voice conversation", status: "available" },
  { id: "agent-handoff", name: "Agent handoff", status: "available" },
  { id: "human-handoff", name: "Human handoff", status: "available" },
];

const providerDetails: Record<
  Exclude<ServiceProvider, "vertex_ai">,
  Pick<OnboardingProvider, "label" | "services">
> = {
  deepgram: {
    label: "Deepgram",
    services: ["Speech to text", "Text to speech"],
  },
  google: { label: "Google AI Studio", services: ["Language model"] },
  zenmux: { label: "Zenmux", services: ["Language model"] },
  rime: { label: "Rime", services: ["Credentials only"] },
  telnyx: { label: "Telnyx", services: ["Telephony"] },
  twilio: { label: "Twilio", services: ["Telephony"] },
};

export function onboardingProvider(
  provider: Exclude<ServiceProvider, "vertex_ai">,
  status: OnboardingProvider["status"],
  options: Pick<
    OnboardingProvider,
    "lastValidatedAt" | "message" | "source"
  > = {},
): OnboardingProvider {
  return { provider, status, ...providerDetails[provider], ...options };
}

export const readyOnboardingState: OnboardingPageState = {
  tenant: { status: "ready", key: "demo-tenant", name: "Demo" },
  providers: [
    onboardingProvider("deepgram", "valid", {
      lastValidatedAt: "2026-09-18T04:30:00Z",
    }),
    onboardingProvider("google", "valid", {
      lastValidatedAt: "2026-09-18T04:31:00Z",
    }),
  ],
  samples: { status: "ready", items: onboardingSamples },
};
