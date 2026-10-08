import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { DefaultsPanel } from "./defaults-panel";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";

afterEach(cleanup);
test("default capability edits preserve participant overrides and untouched source", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake!.capabilities = { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "custom" } } };
  function Harness() {
    const [document, onChange] = useState(initial);
    return <><DefaultsPanel document={document} onChange={onChange} catalog={modelCatalogFixture} credentialNames={{}} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
  }
  render(<Harness />);
  const tts = within(screen.getByRole("region", { name: "Text to speech" }));
  fireEvent.keyDown(tts.getByRole("combobox", { name: "Provider" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "deepgram" }));
  const saved = JSON.parse(screen.getByTestId("source").textContent!);
  expect(saved.defaults.capabilities.text_to_speech).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
  expect(saved.participants).toEqual(initial.source.participants);
  expect(saved.incoming_call).toEqual(initial.source.incoming_call);
});
