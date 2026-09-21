import { expect, test } from "vitest";
import { installedSetupProviders } from "./setupCatalog";

const capabilities = {
  deepgram: ["credential", "credential_validation", "stt", "tts"],
  google: ["credential", "credential_validation"],
  rime: ["credential", "credential_validation"],
  telnyx: ["credential", "credential_validation", "telephony"],
  twilio: ["credential", "credential_validation", "telephony"],
  zenmux: ["credential", "credential_validation"],
};

test("Setup offers installed providers and only their implemented call capabilities", () => {
  const providers = installedSetupProviders(capabilities);
  expect(providers.map((provider) => provider.id)).toEqual([
    "deepgram",
    "rime",
    "google",
    "zenmux",
    "telnyx",
    "twilio",
  ]);
  expect(providers.find((provider) => provider.id === "deepgram")?.capabilities).toEqual([
    "stt",
    "tts",
  ]);
  expect(providers.find((provider) => provider.id === "rime")?.capabilities).toEqual([]);
  expect(providers.find((provider) => provider.id === "google")?.capabilities).toEqual([
    "llm",
  ]);
  expect(providers.find((provider) => provider.id === "telnyx")?.capabilities).toEqual([
    "telephony",
  ]);
  expect(providers.find((provider) => provider.id === "twilio")?.capabilities).toEqual([
    "telephony",
  ]);
});

test("Setup hides missing providers and removes undeclared speech capabilities", () => {
  const providers = installedSetupProviders({
    google: ["credential"],
    deepgram: ["credential", "stt"],
    telnyx: ["telephony"],
  });
  expect(providers.map((provider) => provider.id)).toEqual(["deepgram", "google"]);
  expect(providers[0]?.capabilities).toEqual(["stt"]);
});
