import { modelCatalogFixture } from "./modelCatalogFixtures";
import { expect, test } from "vitest";
import {
  installedSetupProviders,
  providersFor,
  modelRecommendation,
} from "./setupCatalog";

const installedProviders = (capabilities: Parameters<typeof installedSetupProviders>[0]) => installedSetupProviders(capabilities, modelCatalogFixture);

const capabilities = {
  cartesia: ["credential", "stt", "tts"],
  elevenlabs: ["credential", "stt", "tts"],
  deepgram: ["credential", "credential_validation", "stt", "tts"],
  google: ["credential", "llm", "credential_validation", "stt", "tts"],
  openai: ["credential", "llm", "credential_validation", "sts"],
  rime: ["credential", "credential_validation", "tts"],
  telnyx: ["credential", "credential_validation", "telephony"],
  twilio: ["credential", "credential_validation", "telephony"],
  zenmux: ["credential", "llm", "credential_validation"],
};

test("Setup offers installed providers and only their implemented call capabilities", () => {
  const providers = installedProviders(capabilities);
  expect(providers.map((provider) => provider.id)).toEqual([
    "deepgram",
    "rime",
    "cartesia",
    "elevenlabs",
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

test("Cartesia filters capabilities against the installed manifest", () => {
  const [provider] = installedProviders({cartesia: ["credential", "tts"]});
  expect(provider).toMatchObject({id: "cartesia", capabilities: ["tts"], defaultModels: {tts: "sonic-3.6"}});
  expect(providersFor("tts", [{provider: "cartesia", status: "connected"}], [provider!])).toHaveLength(1);
});

test("ElevenLabs offers installed phrase synthesis with its reviewed default model", () => {
  const [provider] = installedProviders({elevenlabs: ["credential", "tts"]});
  expect(provider).toMatchObject({id: "elevenlabs", name: "ElevenLabs", capabilities: ["tts"],
    defaultModels: {tts: "eleven_flash_v2_5"}});
  expect(providersFor("tts", [{provider: "elevenlabs", status: "connected"}], [provider!])).toHaveLength(1);
  expect(provider?.capabilities).not.toContain("stt");
  expect(provider?.capabilities).not.toContain("s2s");
});

test("ElevenLabs offers realtime Scribe and synthesis through one configured service", () => {
  const [provider] = installedProviders({elevenlabs: ["credential", "stt", "tts"]});
  expect(provider).toMatchObject({id: "elevenlabs", capabilities: ["stt", "tts"],
    defaultModels: {stt: "scribe_v2_realtime", tts: "eleven_flash_v2_5"}});
  expect(providersFor("stt", [{provider: "elevenlabs", status: "connected"}], [provider!])).toHaveLength(1);
  expect(provider?.capabilities).not.toContain("s2s");
});

test("Cartesia offers Ink transcription and Sonic synthesis from one service", () => {
  const [provider] = installedProviders({cartesia: ["credential", "stt", "tts"]});
  expect(provider).toMatchObject({id: "cartesia", capabilities: ["stt", "tts"],
    defaultModels: {stt: "ink-2", tts: "sonic-3.6"}});
  expect(providersFor("stt", [{provider: "cartesia", status: "connected"}], [provider!])).toHaveLength(1);
  expect(provider?.capabilities).not.toContain("s2s");
});

test("Setup hides missing providers and removes undeclared speech capabilities", () => {
  const providers = installedProviders({
    google: ["credential", "llm"],
    deepgram: ["credential", "stt"],
    telnyx: ["telephony"],
  });
  expect(providers.map((provider) => provider.id)).toEqual(["deepgram", "google"]);
  expect(providers[0]?.capabilities).toEqual(["stt"]);
});

test("OpenAI speech-to-speech is available with one connected credential", () => {
  const providers = installedProviders(capabilities);
  const connected = [{ provider: "openai", status: "connected" }] as const;
  expect(
    providersFor(
      "s2s",
      connected.map((connection) => ({ ...connection })),
      providers,
    ),
  ).toEqual([expect.objectContaining({ id: "openai" })]);
});


test("Setup advertises configured Gemini Live only when Google STS is installed", () => {
  const providers = installedProviders({google: ["credential", "llm", "stt", "sts", "tts"]});
  expect(providers).toEqual([
    expect.objectContaining({id: "google", capabilities: ["stt", "llm", "tts", "s2s"],
      defaultModels: expect.objectContaining({s2s: "gemini-3.8-live"})}),
  ]);
  expect(installedProviders({google: ["credential", "llm", "stt", "tts"]})[0]?.capabilities).not.toContain("s2s");
});

test("recommended models come from the backend catalog, including the separate Flux voice", () => {
  const providers = installedSetupProviders({deepgram: ["credential", "tts"]}, {
    text_to_speech: {deepgram: [
      {id: "flux", name: "Flux", default: true, voices: {type: "free_text", default: "hannah", parameter: "voice"}},
    ]},
  });
  expect(providers[0]?.defaultModels).toEqual({tts: "flux"});
  expect(modelRecommendation(providers[0]!, "tts")).toBe("flux · hannah");
  expect(providers[0]?.recommendedModels.tts?.voices).toMatchObject({default: "hannah"});
});
