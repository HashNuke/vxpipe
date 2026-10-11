import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { DefaultsPanel } from "./defaults-panel";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { recommendedSelection } from "./seed";

function Harness({ initial = editorFixture, catalog = modelCatalogFixture }: { initial?: SourceDocument; catalog?: typeof modelCatalogFixture }) {
  const [document, onChange] = useState(initial);
  return <><DefaultsPanel document={document} onChange={onChange} catalog={catalog} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
async function chooseMode(name: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Model type" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name }));
}

afterEach(cleanup);
test("default capability edits preserve participant overrides and untouched source", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.defaults = { capabilities: { output_speech_to_text: { provider: "deepgram", model: "flux-general-en" } } };
  initial.source.participants.intake!.capabilities = { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "custom" } } };
  function Harness() {
    const [document, onChange] = useState(initial);
    return <><DefaultsPanel document={document} onChange={onChange} catalog={modelCatalogFixture} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
  }
  render(<Harness />);
  const tts = within(screen.getByRole("region", { name: "Text to speech" }));
  fireEvent.keyDown(tts.getByRole("combobox", { name: "Provider" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "deepgram" }));
  const saved = JSON.parse(screen.getByTestId("source").textContent!);
  expect(saved.defaults.capabilities.text_to_speech).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  expect(saved.defaults.capabilities.output_speech_to_text).toEqual(initial.source.defaults.capabilities?.output_speech_to_text);
  expect(saved.participants).toEqual(initial.source.participants);
  expect(saved.incoming_call).toEqual(initial.source.incoming_call);
});


test("call model defaults show only the selected AI path and keep human transcription separate", () => {
  const initial = structuredClone(editorFixture);
  initial.source.defaults = { capabilities: { output_speech_to_text: { provider: "deepgram", model: "flux-general-en" } } };
  function Harness() {
    const [document, onChange] = useState(initial);
    return <><DefaultsPanel document={document} onChange={onChange} catalog={modelCatalogFixture} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
  }
  render(<Harness />);
  const ai = within(screen.getByRole("region", { name: "AI agents" }));
  expect(ai.getByRole("combobox", { name: "Model type" })).toHaveTextContent("LLM + Text-to-Speech");
  expect(ai.getByRole("region", { name: "Language model" })).toBeInTheDocument();
  expect(ai.getByRole("region", { name: "Text to speech" })).toBeInTheDocument();
  expect(ai.queryByRole("region", { name: "Speech to speech" })).not.toBeInTheDocument();
  expect(ai.queryByRole("region", { name: "Speech to text" })).not.toBeInTheDocument();
  const humans = within(screen.getByRole("region", { name: "Human participants" }));
  expect(humans.getByRole("region", { name: "Speech to text" })).toBeInTheDocument();
  expect(humans.getAllByRole("combobox")).toHaveLength(2);
  expect(screen.queryByText("Output speech to text")).not.toBeInTheDocument();
  expect(JSON.parse(screen.getByTestId("source").textContent!)).toEqual(initial.source);
});

test("changing default AI type replaces incompatible models while retaining compatible overrides and human settings", async () => {
  const initial = structuredClone(editorFixture);
  const stt = { provider: "deepgram", model: "flux-general-en" };
  const sts = { provider: "google", model: "custom-sts", options: { voice: "custom" } };
  initial.source.defaults = { capabilities: {
    model_inference: { provider: "google", model: "custom-llm" },
    text_to_speech: { provider: "cartesia", model: "custom-tts" }, speech_to_text: stt,
  } };
  initial.source.participants.intake!.capabilities = { model_inference: { provider: "google", model: "override" } };
  initial.source.participants.reviewer = { type: "agent", prompt: "Review", capabilities: { speech_to_speech: sts } };
  render(<Harness initial={initial} />);
  await chooseMode("Speech-to-Speech");
  expect(screen.getByRole("region", { name: "Speech to speech" })).toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "Language model" })).not.toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "Text to speech" })).not.toBeInTheDocument();
  expect(saved().defaults.capabilities).toEqual({
    speech_to_speech: recommendedSelection(modelCatalogFixture, "speech_to_speech", "google"), speech_to_text: stt,
  });
  expect(saved().participants.intake).not.toHaveProperty("capabilities");
  expect(saved().participants.reviewer.capabilities).toEqual({ speech_to_speech: sts });
  expect(saved().participants.caller).toEqual(initial.source.participants.caller);
  expect(saved().participants.specialist).toEqual(initial.source.participants.specialist);
  expect(saved().incoming_call).toEqual(initial.source.incoming_call);
  await chooseMode("LLM + Text-to-Speech");
  expect(saved().defaults.capabilities).toEqual({
    model_inference: recommendedSelection(modelCatalogFixture, "model_inference", "deepseek"),
    text_to_speech: recommendedSelection(modelCatalogFixture, "text_to_speech", "cartesia"), speech_to_text: stt,
  });
  expect(saved().participants.reviewer).not.toHaveProperty("capabilities");
  expect(screen.queryByRole("region", { name: "Speech to speech" })).not.toBeInTheDocument();
});

test("saved STS defaults load without mutation and historical model controls stay disabled", () => {
  const initial = structuredClone(editorFixture);
  initial.readOnly = true;
  initial.source.defaults = { capabilities: { speech_to_speech: { provider: "google", model: "saved-sts" } } };
  render(<Harness initial={initial} />);
  expect(screen.getByRole("combobox", { name: "Model type" })).toHaveTextContent("Speech-to-Speech");
  expect(screen.queryByRole("region", { name: "Language model" })).not.toBeInTheDocument();
  for (const control of screen.getAllByRole("combobox")) expect(control).toBeDisabled();
  expect(saved()).toEqual(initial.source);
});

test("a default AI type without available recommended models cannot be selected", async () => {
  render(<Harness catalog={{ ...modelCatalogFixture, speech_to_speech: {} }} />);
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Model type" }), { key: "ArrowDown" });
  expect(await screen.findByRole("option", { name: "Speech-to-Speech" })).toHaveAttribute("aria-disabled", "true");
  expect(saved()).toEqual(editorFixture.source);
});
