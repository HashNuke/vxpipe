import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import type { CapabilitySelection, SourceDocument } from "./types";

export function recommendedSelection(catalog: ModelCatalog, capability: CatalogCapability, provider: string): CapabilitySelection {
  const providers = catalog[capability];
  const models = providers && Object.hasOwn(providers, provider) ? providers[provider] : undefined;
  const model = models?.find((model) => model.default);
  if (!model) throw new Error("No recommended model is available for this provider. Reload the model catalog.");
  const selection: CapabilitySelection = { provider, model: model.id };
  if (model.options) selection.options = structuredClone(model.options);
  if (model.voices) {
    const voice = model.voices.type === "free_text" ? model.voices.default : model.voices.values.find((voice) => voice.default)?.id;
    if (!voice) throw new Error("No recommended voice is available. Reload the model catalog.");
    selection.options = { ...selection.options, [model.voices.parameter]: voice };
  }
  return selection;
}

/** Matches the text-capable development example; voice capabilities are explicit later edits. */
export function newCallSpec(catalog: ModelCatalog): SourceDocument {
  const providers = Object.keys(catalog.model_inference ?? {}).sort();
  const provider = providers.includes("google") ? "google" : providers[0];
  if (!provider) throw new Error("No runnable language model is available. Reload the model catalog.");
  return {
    readOnly: false,
    source: {
      schema_version: "20261004.01",
      incoming_call: { caller: "caller", handled_by: "assistant" },
      defaults: { capabilities: { model_inference: recommendedSelection(catalog, "model_inference", provider) } },
      participants: {
        caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
        assistant: { type: "agent", prompt: "Help the caller concisely.", first_message: { mode: "wait_for_input" }, tools: {}, transfers: [] },
      },
    },
  };
}
