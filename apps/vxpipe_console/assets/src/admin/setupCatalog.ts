import catalog from "./setupCatalog.json";
import type { ServiceProvider, CredentialField } from "./serviceTypes";

export type VoiceCapability = "stt" | "llm" | "tts" | "s2s";
export type SetupProviderId = ServiceProvider;
export type SetupConnection = {
  provider: SetupProviderId;
  status: "connected" | "invalid" | "unavailable" | "disabled";
  source?: "platform" | "tenant";
  telephonyPublicKeyConfigured?: boolean;
  savedFields?: CredentialField[];
};
export type SetupServiceScope =
  | { kind: "platform" }
  | { kind: "tenant"; tenantKey: string; tenantName: string };

// A tenant entry always wins, including a disabled or invalid override.
export function effectiveSetupConnections(
  platform: SetupConnection[],
  tenant: SetupConnection[],
): SetupConnection[] {
  const effective = new Map<SetupProviderId, SetupConnection>();
  for (const item of platform)
    effective.set(item.provider, { ...item, source: "platform" });
  for (const item of tenant)
    effective.set(item.provider, { ...item, source: "tenant" });
  return [...effective.values()];
}
export type SetupTenant = { key: string; name: string; demo?: boolean };
export type SetupProvider = {
  id: SetupProviderId;
  availableInSetup?: boolean;
  name: string;
  description: string;
  // Provider labels and model defaults can include future integrations.
  capabilities: Array<VoiceCapability | "telephony">;
  defaultModels: Partial<Record<VoiceCapability, string>>;
  sampleCapabilities: VoiceCapability[];
};

export const setupProviders = (catalog.providers as SetupProvider[]).filter(
  (provider) => provider.availableInSetup !== false,
);
export type SetupServiceGroup = "ai" | "telephony";
export function providerInGroup(
  provider: SetupProvider,
  group: SetupServiceGroup,
) {
  return group === "telephony"
    ? provider.capabilities.includes("telephony")
    : provider.capabilities.some((capability) => capability !== "telephony");
}
export const voiceCapabilities: VoiceCapability[] = ["stt", "llm", "tts"];
export const capabilityLabels = {
  stt: "Speech-to-text",
  llm: "LLM",
  tts: "Text-to-speech",
  telephony: "Telephony",
  s2s: "Speech-to-speech",
};

export function setupProvider(
  id: SetupProviderId,
  providers = setupProviders,
): SetupProvider {
  return providers.find((provider) => provider.id === id)!;
}

export function providersFor(
  capability: VoiceCapability,
  connections: SetupConnection[],
  providers = setupProviders,
) {
  return providers.filter(
    (provider) =>
      provider.capabilities.includes(capability) &&
      provider.sampleCapabilities.includes(capability) &&
      Boolean(provider.defaultModels[capability]) &&
      connections.some(
        (connection) =>
          connection.provider === provider.id &&
          connection.status === "connected",
      ),
  );
}

export function missingCapabilities(
  connections: SetupConnection[],
  providers = setupProviders,
) {
  return voiceCapabilities.filter(
    (capability) =>
      providersFor(capability, connections, providers).length === 0,
  );
}

export function voiceSetupReady(
  connections: SetupConnection[],
  providers = setupProviders,
) {
  return (
    providersFor("s2s", connections, providers).length > 0 ||
    missingCapabilities(connections, providers).length === 0
  );
}
