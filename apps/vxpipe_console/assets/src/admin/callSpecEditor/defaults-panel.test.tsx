import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { DefaultsPanel } from "./defaults-panel";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
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


test("call model defaults group AI model paths and human transcription without output STT", () => {
  const initial = structuredClone(editorFixture);
  initial.source.defaults = { capabilities: { output_speech_to_text: { provider: "deepgram", model: "flux-general-en" } } };
  function Harness() {
    const [document, onChange] = useState(initial);
    return <><DefaultsPanel document={document} onChange={onChange} catalog={modelCatalogFixture} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
  }
  render(<Harness />);
  const ai = within(screen.getByRole("region", { name: "AI agents" }));
  expect(ai.getByRole("group", { name: "LLM + Text-to-Speech" })).toBeInTheDocument();
  expect(ai.getByRole("group", { name: "Speech-to-Speech" })).toBeInTheDocument();
  expect(ai.queryByRole("region", { name: "Speech to text" })).not.toBeInTheDocument();
  const humans = within(screen.getByRole("region", { name: "Human participants" }));
  expect(humans.getByRole("region", { name: "Speech to text" })).toBeInTheDocument();
  expect(humans.getAllByRole("combobox")).toHaveLength(2);
  expect(screen.queryByText("Output speech to text")).not.toBeInTheDocument();
  expect(JSON.parse(screen.getByTestId("source").textContent!)).toEqual(initial.source);
});
