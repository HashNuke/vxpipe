import { expect, test } from "vitest";
import { onboardingProvider } from "./onboardingFixtures";

test("the onboarding inventory presents working Rime speech", () => {
  expect(onboardingProvider("rime", "valid").services).toEqual(["Text to speech"]);
});

test("the onboarding inventory presents ElevenLabs realtime transcription and synthesis", () => {
  expect(onboardingProvider("elevenlabs", "valid").services).toEqual(["Speech to text", "Text to speech"]);
});
