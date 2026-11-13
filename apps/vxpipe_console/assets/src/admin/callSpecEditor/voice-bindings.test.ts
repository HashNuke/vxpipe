import { expect, test } from "vitest";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { newCallSpec, recommendedSelection } from "./seed";
import { setDefaultAgentModelMode } from "./default-agent-models";
import { setAgentModelMode } from "./agent-models";
const names = Object.fromEntries(["google", "deepgram", "elevenlabs", "openai", "cartesia", "rime"].map(provider => [provider, [provider]]));
test("new selections from mode switches use configured credentials and preserve existing bindings", () => {
  const document = newCallSpec(modelCatalogFixture, { direction: "incoming" });
  const defaults = setDefaultAgentModelMode(document, "speech_to_speech", modelCatalogFixture, names);
  const speech = defaults.source.defaults!.capabilities!.speech_to_speech!;
  expect(speech.credential_name).toBe(speech.provider);
  const participant = setAgentModelMode(document, "assistant", "speech_to_speech", modelCatalogFixture, names);
  const override = participant.source.participants.assistant!.capabilities!.speech_to_speech!;
  expect(override.credential_name).toBe(override.provider);
  expect(recommendedSelection(modelCatalogFixture, "text_to_speech", "elevenlabs", { elevenlabs: ["office"] }).credential_name).toBe("office");
  expect(recommendedSelection(modelCatalogFixture, "text_to_speech", "elevenlabs", { elevenlabs: ["default", "elevenlabs"] }).credential_name).toBe("elevenlabs");
});
