import { expect, test } from "vitest";
import { parseModelCatalog } from "./modelCatalog";

const model = { id: "flux", name: "Flux", default: true, voices: { type: "free_text", default: "hannah", parameter: "voice" } };

test("parses the backend model and separate voice contract", () => {
  const catalog = { text_to_speech: { deepgram: [model] } };
  expect(parseModelCatalog(catalog)).toEqual(catalog);
});

test("a malformed catalog cannot silently replace provider recommendations", () => {
  for (const value of [{ speech_to_text: { deepgram: [{ ...model, options: "invalid" }] } }, null, [], { unknown: {} }, { text_to_speech: { deepgram: [] } },
    { text_to_speech: { deepgram: [model, { ...model, id: "duplicate-default" }] } },
    { text_to_speech: { deepgram: [{ ...model, voices: { type: "free_text", default: "hannah" } }] } },
  ]) expect(() => parseModelCatalog(value)).toThrow("Model catalog could not be loaded");
});
