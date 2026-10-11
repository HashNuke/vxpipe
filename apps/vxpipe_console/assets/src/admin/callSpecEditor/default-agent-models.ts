import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import { agentModelKinds, type AgentModelMode } from "./agent-models";
import { editSource } from "./editSource";
import { recommendedSelection } from "./seed";
import type { CallSpecSource, SourceDocument } from "./types";

export function defaultAgentModelMode(source: CallSpecSource): AgentModelMode {
  return source.defaults?.capabilities?.speech_to_speech ? "speech_to_speech" : "llm";
}

export function canSelectDefaultAgentModels(source: CallSpecSource, mode: AgentModelMode, catalog: ModelCatalog): boolean {
  return agentModelKinds[mode].every((kind) => source.defaults?.capabilities?.[kind]
    || recommendedProvider(catalog, kind));
}

/** Defaults apply to every agent, so incompatible overrides must be removed too. */
export function setDefaultAgentModelMode(document: SourceDocument, mode: AgentModelMode, catalog: ModelCatalog): SourceDocument {
  return editSource(document, (source) => {
    const defaults = (source.defaults ??= {}).capabilities ??= {};
    const incompatible: CatalogCapability[] = mode === "speech_to_speech"
      ? ["model_inference", "text_to_speech"] : ["speech_to_speech", "output_speech_to_text"];
    for (const kind of incompatible) {
      delete defaults[kind];
      for (const participant of Object.values(source.participants)) {
        if (participant.type !== "agent" || !participant.capabilities) continue;
        delete participant.capabilities[kind];
        if (!Object.keys(participant.capabilities).length) delete participant.capabilities;
      }
    }
    for (const kind of agentModelKinds[mode]) {
      if (defaults[kind]) continue;
      const provider = recommendedProvider(catalog, kind);
      if (!provider) throw new Error("No recommended model is available for this model type. Reload the model catalog.");
      defaults[kind] = recommendedSelection(catalog, kind, provider);
    }
  });
}

function recommendedProvider(catalog: ModelCatalog, kind: CatalogCapability): string | undefined {
  return Object.keys(catalog[kind] ?? {}).sort().find((provider) => catalog[kind]![provider]!.some((model) => model.default));
}
