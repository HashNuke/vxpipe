import type { CatalogCapability, ModelCatalog, ModelDescriptor } from "../modelCatalog";
import type { CapabilitySelection, SourceDocument } from "./types";
import { requireIdentifier } from "./editSource";

export type NewCallDirection = { direction: "incoming" } | { direction: "outgoing"; service: string };

export function recommendedSelection(catalog: ModelCatalog, capability: CatalogCapability, provider: string): CapabilitySelection {
  const providers = catalog[capability];
  const models = providers && Object.hasOwn(providers, provider) ? providers[provider] : undefined;
  const model = models?.find((model) => model.default);
  if (!model) throw new Error("No recommended model is available for this provider. Reload the model catalog.");
  return selectionForModel(provider, model);
}

export function selectionForModel(provider: string, model: ModelDescriptor): CapabilitySelection {
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
export function newCallSpec(catalog: ModelCatalog, choice: NewCallDirection): SourceDocument {
  const providers = Object.keys(catalog.model_inference ?? {}).sort();
  const provider = providers.includes("google") ? "google" : providers[0];
  if (!provider) throw new Error("No runnable language model is available. Reload the model catalog.");
  if (choice.direction === "outgoing") {
    if (!choice.service || choice.service === "web") throw new Error("Choose a phone service for outgoing calls.");
    requireIdentifier(choice.service);
  }
  const entry = choice.direction === "outgoing" ? "callee" : "caller";
  return {
    readOnly: false,
    source: {
      schema_version: "20261004.01",
      ...(choice.direction === "outgoing" ? { outgoing_call: { callee: entry, handled_by: "assistant" } } : { incoming_call: { caller: entry, handled_by: "assistant" } }),
      defaults: { capabilities: { model_inference: recommendedSelection(catalog, "model_inference", provider) } },
      participants: {
        [entry]: { type: "human", connection: choice.direction === "outgoing"
          ? { service: choice.service, mode: "dial", admission: "start_call" }
          : { service: "web", mode: "receive", admission: "start_call" } },
        assistant: { type: "agent", prompt: "Help the caller concisely.", ...(choice.direction === "incoming" ? { first_message: { mode: "wait_for_input" as const } } : {}), tools: {}, transfers: [] },
      },
    },
  };
}
