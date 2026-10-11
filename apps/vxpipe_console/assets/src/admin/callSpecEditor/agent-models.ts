import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import { editSource } from "./editSource";
import { agent } from "./edits";
import { recommendedSelection } from "./seed";
import type { CallSpecSource, SourceDocument } from "./types";

export type AgentModelMode = "llm" | "speech_to_speech";
export const agentModelKinds: Record<AgentModelMode, CatalogCapability[]> = {
  llm: ["model_inference", "text_to_speech"],
  speech_to_speech: ["speech_to_speech"],
};

export function agentModelMode(source: CallSpecSource, key: string): AgentModelMode {
  return agent(source, key).capabilities?.speech_to_speech || source.defaults?.capabilities?.speech_to_speech
    ? "speech_to_speech" : "llm";
}

export function canSelectAgentModels(source: CallSpecSource, key: string, mode: AgentModelMode, catalog: ModelCatalog): boolean {
  const target = agent(source, key);
  return agentModelKinds[mode].every((kind) => target.capabilities?.[kind] || source.defaults?.capabilities?.[kind]
    || Object.values(catalog[kind] ?? {}).some((models) => models.some((model) => model.default)));
}

/** A mode change keeps other agents' effective selections when removing conflicting defaults. */
export function setAgentModelMode(document: SourceDocument, key: string, mode: AgentModelMode, catalog: ModelCatalog): SourceDocument {
  return editSource(document, (source) => {
    const target = agent(source, key);
    const capabilities = target.capabilities ??= {};
    const incompatible: CatalogCapability[] = mode === "speech_to_speech"
      ? ["model_inference", "text_to_speech", "output_speech_to_text"]
      : ["speech_to_speech", "output_speech_to_text"];

    // The source contract has no per-participant "disable inherited capability" value.
    // Move only conflicting defaults to the agents that still use them before clearing them.
    for (const kind of incompatible) {
      const inherited = source.defaults?.capabilities?.[kind];
      if (inherited) {
        for (const [otherKey, other] of Object.entries(source.participants)) {
          if (otherKey !== key && other.type === "agent") {
            other.capabilities ??= {};
            other.capabilities[kind] ??= structuredClone(inherited);
          }
        }
        delete source.defaults!.capabilities![kind];
      }
      delete capabilities[kind];
    }
    delete capabilities.speech_to_text;

    for (const kind of agentModelKinds[mode]) {
      if (capabilities[kind] || source.defaults?.capabilities?.[kind]) continue;
      const provider = Object.keys(catalog[kind] ?? {}).sort().find((provider) => catalog[kind]![provider]!.some((model) => model.default));
      if (!provider) throw new Error("No recommended model is available for this model type. Reload the model catalog.");
      capabilities[kind] = recommendedSelection(catalog, kind, provider);
    }

    if (source.defaults?.capabilities && !Object.keys(source.defaults.capabilities).length) delete source.defaults.capabilities;
    if (source.defaults && !Object.keys(source.defaults).length) delete source.defaults;
    if (!Object.keys(capabilities).length) delete target.capabilities;
  });
}
