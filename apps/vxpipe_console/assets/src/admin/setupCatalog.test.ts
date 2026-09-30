import { expect, test } from "vitest";
import {
  installedSetupProviders,
  providersFor,
} from "./setupCatalog";

const capabilities = {
  cartesia: ["credential", "tts"],
  deepgram: ["credential", "credential_validation", "stt", "tts"],
  google: ["credential", "credential_validation", "stt", "tts"],
  openai: ["credential", "credential_validation", "sts"],
  rime: ["credential", "credential_validation", "tts"],
  telnyx: ["credential", "credential_validation", "telephony"],
  twilio: ["credential", "credential_validation", "telephony"],
  zenmux: ["credential", "credential_validation"],
};

test("Setup offers installed providers and only their implemented call capabilities", () => {
  const providers = installedSetupProviders(capabilities);
  expect(providers.map((provider) => provider.id)).toEqual([
    "deepgram",
    "rime",
    "cartesia",
    "google",
    "openai",
    "zenmux",
    "telnyx",
    "twilio",
  ]);
  expect(providers.find((provider) => provider.id === "deepgram")?.capabilities).toEqual([
    "stt",
    "tts",
  ]);
  expect(providers.find((provider) => provider.id === "rime")?.capabilities).toEqual(["tts"]);
  expect(providers.find((provider) => provider.id === "google")?.capabilities).toEqual([
    "stt",
    "llm",
    "tts",
  ]);
  expect(providers.find((provider) => provider.id === "openai")?.capabilities).toEqual([
    "llm",
    "s2s",
  ]);
  expect(providers.find((provider) => provider.id === "telnyx")?.capabilities).toEqual([
    "telephony",
  ]);
  expect(providers.find((provider) => provider.id === "twilio")?.capabilities).toEqual([
    "telephony",
  ]);
});

test("Cartesia offers verified TTS without advertising transcription or agent speech", () => {
  const [provider] = installedSetupProviders({cartesia: ["credential", "tts"]});
  expect(provider).toMatchObject({id: "cartesia", capabilities: ["tts"], defaultModels: {tts: "sonic-3.6"}});
  expect(providersFor("tts", [{provider: "cartesia", status: "connected"}], [provider!])).toHaveLength(1);
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

test("OpenAI speech-to-speech is available with one connected credential", () => {
  const providers = installedSetupProviders(capabilities);
  const connected = [{ provider: "openai", status: "connected" }] as const;
  expect(
    providersFor(
      "s2s",
      connected.map((connection) => ({ ...connection })),
      providers,
    ),
  ).toEqual([expect.objectContaining({ id: "openai" })]);
});
