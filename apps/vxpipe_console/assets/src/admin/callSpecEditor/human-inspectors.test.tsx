import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { InboundInspector } from "./inbound-inspector";
import { HumanInspector } from "./human-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { validateSource } from "./validation";

afterEach(cleanup);
const lookups = { telephonyServices: [{ key: "phone", name: "Reception phone" }], credentialNames: { deepgram: ["production"] }, mcpIntegrations: [] };
function Harness({ entry = false, initial = editorFixture }: { entry?: boolean; initial?: SourceDocument }) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("specialist");
  const props = { document, onChange, issues: validateSource(document.source), catalog: modelCatalogFixture, lookups };
  return <>{entry ? <InboundInspector {...props} /> : Object.hasOwn(document.source.participants, participantKey) && <HumanInspector {...props} participantKey={participantKey} onRenamed={onRenamed} />}
    <output data-testid="source">{JSON.stringify(document.source)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}
function outgoing(): SourceDocument {
  const initial = structuredClone(editorFixture);
  delete initial.source.incoming_call;
  initial.source.outgoing_call = { callee: "caller", handled_by: "intake" };
  initial.source.participants.caller = { type: "human", connection: { service: "phone", mode: "dial" } };
  return initial;
}
test("entry connection edits preserve incoming admission and remove phone fields when returning to web", async () => {
  render(<Harness entry />);
  expect(saved()).toEqual(editorFixture.source);
  expect(screen.queryByRole("button", { name: "Delete participant" })).not.toBeInTheDocument();
  await choose("Connection service", "Reception phone");
  fireEvent.change(screen.getByRole("textbox", { name: "Phone number" }), { target: { value: "+15550001000" } });
  expect(saved().participants.caller.connection).toEqual({ service: "phone", mode: "receive", admission: "start_call", number: "+15550001000" });
  await choose("Connection service", "Web");
  expect(saved().participants.caller.connection).toEqual({ service: "web", mode: "receive", admission: "start_call" });
});
test("outgoing entry offers request or fixed number, never variable or web, and validates its ring timeout", async () => {
  render(<Harness entry initial={outgoing()} />);
  expect(saved()).toEqual(outgoing().source);
  expect(screen.getByRole("combobox", { name: "Number source" })).toHaveTextContent("Outgoing request (to)");
  await choose("Number source", "Fixed number");
  fireEvent.change(screen.getByRole("textbox", { name: "Phone number" }), { target: { value: "+15550001000" } });
  await choose("Number source", "Outgoing request (to)");
  expect(saved().participants.caller.connection).not.toHaveProperty("number");
  expect(saved().participants.caller.connection).not.toHaveProperty("number_from_variable");
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Connection service" }), { key: "ArrowDown" });
  expect(screen.queryByRole("option", { name: "Web" })).not.toBeInTheDocument();
  fireEvent.click(await screen.findByRole("option", { name: "Reception phone" }));
  fireEvent.change(screen.getByRole("spinbutton", { name: "Ring timeout (ms)" }), { target: { value: "4999" } });
  expect(screen.getByRole("spinbutton", { name: "Ring timeout (ms)" })).toHaveAttribute("aria-invalid", "true");
  fireEvent.change(screen.getByRole("spinbutton", { name: "Ring timeout (ms)" }), { target: { value: "" } });
  expect(saved().outgoing_call).not.toHaveProperty("ring_timeout_ms");
});
test("opening audio requires explicit speech selection and supports text, file and removal", async () => {
  render(<Harness entry />);
  fireEvent.click(screen.getByRole("switch", { name: "Opening audio" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Opening message" }), { target: { value: "Welcome to reception." } });
  await choose("Provider", "deepgram");
  expect(saved().opening_audio).toEqual({ type: "text", text: "Welcome to reception.", text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } });
  await choose("Opening audio type", "Audio file URL");
  fireEvent.change(screen.getByRole("textbox", { name: "Audio file URL" }), { target: { value: "https://example.test/welcome.wav" } });
  expect(saved().opening_audio).toEqual({ type: "file_url", url: "https://example.test/welcome.wav" });
  fireEvent.click(screen.getByRole("switch", { name: "Opening audio" }));
  expect(saved()).not.toHaveProperty("opening_audio");
});
test("human destinations switch between phone, string variable and web without stale routing fields", async () => {
  render(<Harness />);
  await choose("Connection service", "Reception phone");
  await choose("Number source", "Call variable");
  await choose("Variable section", "appointment");
  await choose("Phone variable", "date");
  expect(saved().participants.specialist.connection).toEqual({ service: "phone", mode: "dial", admission: "transfer", number_from_variable: { section: "appointment", variable: "date" } });
  await choose("Number source", "Fixed number");
  expect(saved().participants.specialist.connection).not.toHaveProperty("number_from_variable");
  await choose("Connection service", "Web");
  expect(saved().participants.specialist.connection).toEqual({ service: "web", mode: "receive", admission: "transfer" });
});
test("human identity edits rewrite references, retain literal text and reject collisions", () => {
  render(<Harness />);
  const key = screen.getByRole("textbox", { name: "Participant key" });
  fireEvent.change(key, { target: { value: "intake" } }); fireEvent.blur(key);
  expect(screen.getByRole("alert")).toHaveTextContent("already exists");
  fireEvent.change(key, { target: { value: "support" } }); fireEvent.blur(key);
  expect(saved().participants.intake.transfers).toEqual(["support"]);
  expect(saved().participants.support.transfer_notice).toBe(editorFixture.source.participants.specialist!.type === "human" ? editorFixture.source.participants.specialist.transfer_notice : undefined);
  fireEvent.change(screen.getByRole("textbox", { name: "Description" }), { target: { value: "Support team" } });
  fireEvent.change(screen.getByRole("textbox", { name: "Private briefing" }), { target: { value: "A caller needs your help." } });
  fireEvent.change(screen.getByRole("spinbutton", { name: "Transfer attempt timeout (ms)" }), { target: { value: "45000" } });
  expect(saved().participants.support).toMatchObject({ description: "Support team", transfer_notice: "A caller needs your help." });
  expect(saved().transfer_policy).toEqual({ attempt_timeout_ms: 45000 });
});
test("deleting a human destination confirms removal and cleans transfer references", async () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Delete participant" }));
  expect(saved().participants).toHaveProperty("specialist");
  fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Delete participant" }));
  expect(saved().participants).not.toHaveProperty("specialist");
  expect(saved().participants.intake.transfers).toEqual([]);
});
test("human capabilities show inheritance and edit only the selected participant", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.defaults = { capabilities: { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "haley" } } } };
  render(<Harness initial={initial} />);
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Voice and model" }), { button: 0 });
  const tts = within(screen.getByRole("region", { name: "Text to speech" }));
  expect(tts.getByText(/Inherited: deepgram · flux · haley/)).toBeInTheDocument();
  fireEvent.keyDown(tts.getByRole("combobox", { name: "Provider" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "deepgram" }));
  expect(saved().participants.specialist.capabilities.text_to_speech.options.voice).toBe("hannah");
  expect(saved().defaults).toEqual(initial.source.defaults);
  expect(tts.getByText("Participant override")).toBeInTheDocument();
  expect(tts.getByText(/Call default: deepgram · flux · haley/)).toBeInTheDocument();
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Presence" }), { button: 0 });
  await choose("Record audio", "Deny");
  expect(saved().participants.specialist.while_present).toEqual({ record_audio: false });
});
test("read-only entry and destination inspectors preserve source and disable all edits", () => {
  const initial = { ...editorFixture, readOnly: true };
  const view = render(<Harness initial={initial} />);
  for (const role of ["textbox", "combobox", "spinbutton"] as const) for (const control of screen.getAllByRole(role)) expect(control).toBeDisabled();
  expect(screen.getByRole("button", { name: "Delete participant" })).toBeDisabled();
  view.unmount(); render(<Harness entry initial={initial} />);
  expect(screen.getByRole("switch", { name: "Opening audio" })).toBeDisabled();
  expect(saved()).toEqual(initial.source);
});

test("clearing optional description and briefing removes them instead of saving invalid empty text", () => {
  const view = render(<Harness />);
  fireEvent.change(screen.getByRole("textbox", { name: "Description" }), { target: { value: "" } });
  fireEvent.change(screen.getByRole("textbox", { name: "Private briefing" }), { target: { value: "" } });
  expect(saved().participants.specialist).not.toHaveProperty("description");
  expect(saved().participants.specialist).not.toHaveProperty("transfer_notice");
  view.unmount(); render(<Harness entry />);
  fireEvent.change(screen.getByRole("textbox", { name: "Description" }), { target: { value: "Caller details" } });
  fireEvent.change(screen.getByRole("textbox", { name: "Description" }), { target: { value: "" } });
  expect(saved().participants.caller).not.toHaveProperty("description");
});

test("opening a saved document preserves nullable fields, omitted admission and explicit voice options", () => {
  const initial = outgoing();
  initial.source.opening_audio = { type: "text", text: "Welcome", text_to_speech: { provider: "deepgram", model: "flux-haley-en", options: { encoding: "linear16" } } };
  initial.source.participants.caller!.description = null;
  const view = render(<Harness entry initial={initial} />);
  expect(screen.getByRole("combobox", { name: "Model" })).toHaveTextContent("flux-haley-en (saved)");
  expect(saved()).toEqual(initial.source);
  view.unmount();
  initial.source.opening_audio = null;
  render(<Harness entry initial={initial} />);
  expect(screen.getByRole("switch", { name: "Opening audio" })).not.toBeChecked();
  expect(saved()).toEqual(initial.source);
});

test("an inherited provider absent from the catalog stays visible without changing saved source", () => {
  const initial = structuredClone(editorFixture);
  initial.source.defaults = { capabilities: { text_to_speech: { provider: "__proto__", model: "saved" } } };
  render(<Harness initial={initial} />);
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Voice and model" }), { button: 0 });
  expect(screen.getByText("Inherited: __proto__ · saved")).toBeInTheDocument();
  expect(saved()).toEqual(initial.source);
});
