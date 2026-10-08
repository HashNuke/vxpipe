import type { CatalogCapability, ModelCatalog, ModelDescriptor } from "./modelCatalog";
import catalog from "./setupCatalog.json";
import type { ServiceProvider, CredentialField } from "./serviceTypes";

export type VoiceCapability = "stt" | "llm" | "tts" | "s2s";
export type SetupProviderId = ServiceProvider;
export type SetupConnection = {
  provider: SetupProviderId;
  status: "connected" | "invalid" | "unavailable";
  source?: "platform" | "tenant";
  telephonyPublicKeyConfigured?: boolean;
  savedFields?: CredentialField[];
};
export type SetupServiceScope =
  | { kind: "platform" }
  | { kind: "tenant"; tenantKey: string; tenantName: string };

// A tenant entry always wins, including an invalid override.
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
  name: string;
  description: string;
  capabilities: Array<VoiceCapability | "telephony">;
  defaultModels: Partial<Record<VoiceCapability, string>>;
  recommendedModels: Partial<Record<VoiceCapability, ModelDescriptor>>;
  sampleCapabilities: VoiceCapability[];
};

export const setupProviders: SetupProvider[] = catalog.providers.map((provider) => ({
  ...provider,
  capabilities: provider.capabilities as SetupProvider["capabilities"],
  sampleCapabilities: provider.sampleCapabilities as VoiceCapability[],
  id: provider.id as SetupProviderId,
  defaultModels: {},
  recommendedModels: {},
}));
const catalogCapability: Record<VoiceCapability, CatalogCapability> = {
  stt: "speech_to_text", llm: "model_inference", tts: "text_to_speech", s2s: "speech_to_speech",
};
export type ProviderCapabilities = Record<string, string[]>;

export function installedSetupProviders(
  installed: ProviderCapabilities,
  models: ModelCatalog,
): SetupProvider[] {
  return setupProviders.flatMap((provider) => {
    const declared = installed[provider.id];
    if (!declared?.includes("credential")) return [];
    const capabilities = provider.capabilities.filter(
      (capability) =>
        declared.includes(capability === "s2s" ? "sts" : capability),
    );
    const recommendedModels = Object.fromEntries(
      capabilities.filter((capability): capability is VoiceCapability => capability !== "telephony")
        .flatMap((capability) => {
          const recommended = models[catalogCapability[capability]]?.[provider.id]?.find((model) => model.default);
          return recommended ? [[capability, recommended]] : [];
        }),
    ) as SetupProvider["recommendedModels"];
    return [
      {
        ...provider,
        capabilities,
        sampleCapabilities: provider.sampleCapabilities.filter((capability) =>
          capabilities.includes(capability),
        ),
        recommendedModels,
        defaultModels: Object.fromEntries(
          Object.entries(recommendedModels).map(([capability, model]) => [capability, model.id]),
        ),
      },
    ];
  });
}
export function modelRecommendation(provider: SetupProvider, capability: VoiceCapability): string {
  const model = provider.recommendedModels[capability];
  if (!model) return "";
  const voice = model.voices?.type === "free_text"
    ? model.voices.default
    : model.voices?.values.find((voice) => voice.default)?.id;
  return voice ? `${model.id} · ${voice}` : model.id;
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
