import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import type { CapabilitySelection } from "./types";
import { CredentialNamesContext } from "./credential-names";
import { VoiceCatalogContext, type VoiceCatalogClient } from "../voiceCatalog";
import { CapabilityFields } from "./capability-fields";

afterEach(cleanup);
const catalog: ModelCatalog = { text_to_speech: {
  deepgram: [{ id: "flux", name: "Flux", default: true, voices: { type: "free_text", parameter: "voice", default: "hannah" } }],
  other: [
    { id: "first", name: "First", default: false, voices: null },
    { id: "recommended", name: "Recommended model", default: true, options: { sample_rate: 24000 }, voices: { type: "list", parameter: "speaker", values: [
      { id: "a", name: "Alpha", default: false }, { id: "b", name: "Beta", default: true },
    ] } },
  ],
}, speech_to_text: {
  deepgram: [{ id: "flux-general-en", name: "Flux", default: true, voices: null }],
  google: [{ id: "live", name: "Live", default: true, voices: null }, { id: "next", name: "Next", default: false, voices: null }],
} };
const voiceClient: VoiceCatalogClient = {
  describe: async () => ({ providerName: "Test", modelName: "Test model", search: true, filters: [] }),
  get: vi.fn(async (_scope, id) => ({ id, name: id, attributes: [] })),
  list: async () => ({ voices: [{ id: "haley", name: "Haley", attributes: [] }, { id: "a", name: "Alpha", attributes: [] }], nextCursor: null }),
};
async function chooseVoice(name: string) {
  fireEvent.click(screen.getByRole("button", { name: /^Voice:/ }));
  fireEvent.click(await screen.findByRole("radio", { name: new RegExp(name) }));
  fireEvent.click(screen.getByRole("button", { name: "Use voice" }));
}
function Harness({ initial, readOnly = false, kind = "text_to_speech" }: { initial?: CapabilitySelection; readOnly?: boolean; kind?: CatalogCapability }) {
  const [value, onChange] = useState(initial);
  return <VoiceCatalogContext value={voiceClient}><CapabilityFields kind={kind} path={["defaults", "capabilities", kind]} value={value} onChange={onChange} catalog={catalog} disabled={readOnly} />
    <output data-testid="selection">{JSON.stringify(value ?? null)}</output></VoiceCatalogContext>;
}
const saved = () => JSON.parse(screen.getByTestId("selection").textContent!);
async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}
test("choosing a provider selects its public recommended model and a separate voice picker", async () => {
  render(<Harness />);
  expect(saved()).toBeNull();
  await choose("Provider", "deepgram");
  expect(saved()).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  expect(screen.getByRole("combobox", { name: "Model" })).toHaveTextContent("Flux");
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Model" }), { key: "ArrowDown" });
  expect((await screen.findAllByRole("option")).map((option) => option.textContent)).toEqual(["Flux"]);
  fireEvent.keyDown(screen.getByRole("listbox"), { key: "Escape" });
  expect(screen.queryByRole("combobox", { name: "Credential" })).not.toBeInTheDocument();
  await chooseVoice("Haley");
  expect(saved().model).toBe("flux");
  expect(saved().options.voice).toBe("haley");
});
test("switching providers resets model, voice and credentials using descriptor-owned options", async () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", credential_name: "production", options: { voice: "haley" }, provider_options: { old: true } }} />);
  await choose("Provider", "other");
  expect(saved()).toEqual({ provider: "other", model: "recommended", options: { sample_rate: 24000, speaker: "b" } });
  await chooseVoice("Alpha");
  expect(saved()).toMatchObject({ options: { speaker: "a", sample_rate: 24000 } });
  await choose("Model", "First");
  expect(saved()).toEqual({ provider: "other", model: "first" });
});
test("existing credential bindings stay in source without a credential control", async () => {
  const initial = { provider: "deepgram", model: "flux", credential_name: "production", options: { voice: "custom", sample_rate: 48000 }, provider_options: { nested: { keep: [1, null] } } };
  render(<Harness initial={initial} />);
  expect(saved()).toEqual(initial);
  expect(screen.queryByRole("combobox", { name: "Credential" })).not.toBeInTheDocument();
  await chooseVoice("Haley");
  expect(saved()).toEqual({ ...initial, options: { ...initial.options, voice: "haley" } });
});
test("legacy combined model IDs stay visible without migration and can be explicitly replaced", async () => {
  const initial = { provider: "deepgram", model: "flux-haley-en", options: { encoding: "linear16" } };
  render(<Harness initial={initial} />);
  expect(saved()).toEqual(initial);
  expect(screen.getByRole("combobox", { name: "Model" })).toHaveTextContent("flux-haley-en (saved)");
  await choose("Model", "Flux");
  expect(saved()).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  await choose("Provider", "Not configured");
  expect(saved()).toBeNull();
});
test("historical selections disable every mutation control", () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", options: { voice: "saved" } }} readOnly />);
  for (const control of screen.getAllByRole("combobox")) expect(control).toBeDisabled();
  expect(screen.getByRole("button", { name: /^Voice:/ })).toBeDisabled();
});

test("advanced options are preserved without generic option controls", async () => {
  const initial = { provider: "deepgram", model: "flux", options: { voice: "custom", sample_rate: 24000 }, provider_options: { nested: { retries: 2 } } };
  render(<Harness initial={initial} />);
  expect(screen.queryByRole("region", { name: "Options" })).not.toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "Provider options" })).not.toBeInTheDocument();
  await chooseVoice("Haley");
  expect(saved()).toEqual({ ...initial, options: { ...initial.options, voice: "haley" } });
});

test.each([true, false])("API-authored vad=%s survives provider and model changes without a control", async (vad) => {
  render(<Harness kind="speech_to_text" initial={{ provider: "deepgram", model: "flux-general-en", vad }} />);
  await choose("Provider", "google");
  expect(saved()).toEqual({ provider: "google", model: "live", vad });
  await choose("Model", "Next");
  expect(saved()).toEqual({ provider: "google", model: "next", vad });
  expect(screen.queryByRole("checkbox", { name: /vad/i })).not.toBeInTheDocument();
  expect(screen.queryByRole("switch", { name: /vad/i })).not.toBeInTheDocument();
});


test("voice requests use explicit and inherited connection names", async () => {
  const selection = { provider: "deepgram", model: "flux", credential_name: "office", options: { voice: "haley" } };
  const onChange = vi.fn();
  render(<VoiceCatalogContext value={voiceClient}><CapabilityFields kind="text_to_speech" path={["participant"]} value={selection} inherited={selection} catalog={catalog} onChange={onChange} /></VoiceCatalogContext>);
  await screen.findByRole("button", { name: "Voice: haley" });
  expect(voiceClient.get).toHaveBeenLastCalledWith(expect.objectContaining({ credential_name: "office" }), "haley", expect.any(AbortSignal));
  await chooseVoice("Alpha");
  expect(onChange).toHaveBeenCalledWith({ ...selection, options: { voice: "a" } });
});

test("without a catalog client the manual voice input is unavailable", () => {
  render(<CapabilityFields kind="text_to_speech" path={["voice"]} value={{ provider: "deepgram", model: "flux", options: { voice: "saved" } }} catalog={catalog} onChange={vi.fn()} />);
  expect(screen.queryByRole("textbox", { name: "Voice" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Voice: saved" })).toBeDisabled();
});


test("new provider selections bind to the configured connection while model changes keep it", async () => {
  render(<CredentialNamesContext value={{ deepgram: ["office"] }}><Harness /></CredentialNamesContext>);
  await choose("Provider", "deepgram");
  expect(saved().credential_name).toBe("office");
  expect(voiceClient.get).toHaveBeenLastCalledWith(expect.objectContaining({ credential_name: "office" }), "hannah", expect.any(AbortSignal));
});
