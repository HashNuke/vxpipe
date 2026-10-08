import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import type { ModelCatalog } from "../modelCatalog";
import type { CapabilitySelection } from "./types";
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
} };
function Harness({ initial, readOnly = false }: { initial?: CapabilitySelection; readOnly?: boolean }) {
  const [value, onChange] = useState(initial);
  return <><CapabilityFields kind="text_to_speech" path={["defaults", "capabilities", "text_to_speech"]} value={value} onChange={onChange} catalog={catalog} credentialNames={{ deepgram: ["production"], other: ["speech"] }} disabled={readOnly} />
    <output data-testid="selection">{JSON.stringify(value ?? null)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("selection").textContent!);
async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}
test("choosing a provider selects its public recommended model and separate free-text voice", async () => {
  render(<Harness />);
  expect(saved()).toBeNull();
  await choose("Provider", "deepgram");
  expect(saved()).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  expect(screen.getByRole("combobox", { name: "Model" })).toHaveTextContent("Flux · Recommended");
  fireEvent.change(screen.getByRole("textbox", { name: "Voice" }), { target: { value: "haley" } });
  expect(saved().model).toBe("flux");
  expect(saved().options.voice).toBe("haley");
});
test("switching providers resets model, voice and credentials using descriptor-owned options", async () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", credential_name: "production", options: { voice: "haley" }, provider_options: { old: true } }} />);
  await choose("Provider", "other");
  expect(saved()).toEqual({ provider: "other", model: "recommended", options: { sample_rate: 24000, speaker: "b" } });
  await choose("Voice", "Alpha");
  await choose("Credential", "speech");
  expect(saved()).toMatchObject({ credential_name: "speech", options: { speaker: "a", sample_rate: 24000 } });
  await choose("Model", "First");
  expect(saved()).toEqual({ provider: "other", model: "first", credential_name: "speech" });
});
test("opening an existing selection preserves saved choices and all unedited options", async () => {
  const initial = { provider: "deepgram", model: "flux", options: { voice: "custom", sample_rate: 48000 }, provider_options: { nested: { keep: [1, null] } } };
  render(<Harness initial={initial} />);
  expect(saved()).toEqual(initial);
  await choose("Credential", "production");
  expect(saved()).toEqual({ ...initial, credential_name: "production" });
});
test("legacy combined model IDs stay visible without migration and can be explicitly replaced", async () => {
  const initial = { provider: "deepgram", model: "flux-haley-en", options: { encoding: "linear16" } };
  render(<Harness initial={initial} />);
  expect(saved()).toEqual(initial);
  expect(screen.getByRole("combobox", { name: "Model" })).toHaveTextContent("flux-haley-en (saved)");
  await choose("Model", "Flux · Recommended");
  expect(saved()).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  await choose("Provider", "Use default");
  expect(saved()).toBeNull();
});
test("historical selections disable every mutation control", () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", options: { voice: "saved" } }} readOnly />);
  for (const control of screen.getAllByRole("combobox")) expect(control).toBeDisabled();
  expect(screen.getByRole("textbox", { name: "Voice" })).toBeDisabled();
});

test("structured option edits retain the separate voice and preserve nested provider options", () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", options: { voice: "custom", sample_rate: 24000 }, provider_options: { nested: { retries: 2 } } }} />);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Options / sample_rate" }), { target: { value: "48000" } });
  fireEvent.change(screen.getByRole("spinbutton", { name: "Provider options / nested / retries" }), { target: { value: "3" } });
  expect(saved()).toEqual({ provider: "deepgram", model: "flux", options: { voice: "custom", sample_rate: 48000 }, provider_options: { nested: { retries: 3 } } });
  expect(screen.queryByRole("textbox", { name: "Options / voice" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Clear Options" }));
  expect(saved().options).toEqual({ voice: "custom" });
  fireEvent.click(screen.getByRole("button", { name: "Clear Provider options" }));
  expect(saved()).not.toHaveProperty("provider_options");
});

test("an option cannot replace the separately edited voice parameter", () => {
  render(<Harness initial={{ provider: "deepgram", model: "flux", options: { voice: "custom", sample_rate: 24000 } }} />);
  const key = screen.getByRole("textbox", { name: "Options / sample_rate key" });
  fireEvent.change(key, { target: { value: "voice" } }); fireEvent.blur(key);
  expect(screen.getByRole("alert")).toHaveTextContent("already exists");
  expect(saved().options).toEqual({ voice: "custom", sample_rate: 24000 });
});
