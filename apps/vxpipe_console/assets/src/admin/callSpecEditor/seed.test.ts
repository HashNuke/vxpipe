import { expect, test } from "vitest";
import { newCallSpec, recommendedSelection } from "./seed";
import { validateSource } from "./validation";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { ModelCatalog } from "../modelCatalog";

test("outgoing seeds dial the selected service and use the outgoing first-message default", () => {
  const document = newCallSpec(modelCatalogFixture, { direction: "outgoing", service: "office" });
  expect(document.source.incoming_call).toBeUndefined();
  expect(document.source.outgoing_call).toEqual({ callee: "caller", handled_by: "assistant" });
  expect(document.source.participants.caller).toMatchObject({ type: "human", connection: { service: "office", mode: "dial", admission: "start_call" } });
  expect(document.source.participants.assistant).not.toHaveProperty("first_message");
  expect(document.source.participants.assistant).toHaveProperty("prompt", "");
  expect(validateSource(document.source).map((issue) => issue.path)).toEqual([["participants", "assistant", "prompt"]]);
  expect(() => newCallSpec(modelCatalogFixture, { direction: "outgoing", service: "web" })).toThrow("phone service");
});

test("a new spec starts with an incoming web caller and agent using the catalog recommendation", () => {
  const catalog: ModelCatalog = { model_inference: { custom: [
    { id: "old-model", name: "Old", default: false, voices: null },
    { id: "new-model", name: "New", default: true, voices: null },
  ] } };
  const doc = newCallSpec(catalog, { direction: "incoming" });
  expect(doc.readOnly).toBe(false);
  expect(doc.source.incoming_call).toEqual({ caller: "caller", handled_by: "assistant" });
  expect(doc.source.participants.caller).toMatchObject({ type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } });
  expect(doc.source.participants.assistant).toMatchObject({ type: "agent", first_message: { mode: "wait_for_input" }, transfers: [], tools: {} });
  expect(doc.source.defaults?.capabilities).toEqual({ model_inference: { provider: "custom", model: "new-model" } });
  expect(doc.source.participants.assistant).toHaveProperty("prompt", "");
  expect(validateSource(doc.source).map((issue) => issue.path)).toEqual([["participants", "assistant", "prompt"]]);
  doc.source.participants.assistant!.description = "Changed";
  expect(newCallSpec(catalog, { direction: "incoming" }).source.participants.assistant?.description).toBeUndefined();
});

test("voice recommendations use descriptor-owned parameters and never combine the public model ID", () => {
  expect(recommendedSelection(modelCatalogFixture, "text_to_speech", "deepgram")).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  const rime = recommendedSelection(modelCatalogFixture, "text_to_speech", "rime");
  expect(rime.options).toHaveProperty("speaker");
  expect(rime.options).not.toHaveProperty("voice");
  expect(recommendedSelection(modelCatalogFixture, "speech_to_speech", "openai").options).toHaveProperty("voice");
});

test("new source prefers the existing Google default and fails clearly without a runnable model catalog", () => {
  expect(newCallSpec(modelCatalogFixture, { direction: "incoming" }).source.defaults?.capabilities?.model_inference?.provider).toBe("google");
  expect(() => newCallSpec({}, { direction: "incoming" })).toThrow("model");
  expect(() => recommendedSelection(modelCatalogFixture, "text_to_speech", "missing")).toThrow("model");
});

test("adapter-owned public options accompany a recommended model", () => {
  const catalog: ModelCatalog = { speech_to_text: { deepgram: [{ id: "flux-general-multi", name: "Flux", default: true, voices: null, options: { encoding: "linear16", sample_rate: 48000 } }] } };
  expect(recommendedSelection(catalog, "speech_to_text", "deepgram")).toEqual({ provider: "deepgram", model: "flux-general-multi", options: { encoding: "linear16", sample_rate: 48000 } });
});
