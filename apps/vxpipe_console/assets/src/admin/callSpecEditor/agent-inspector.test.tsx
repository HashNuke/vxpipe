import { toolCatalogFixture } from "./toolCatalogFixture";
import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { recommendedSelection } from "./seed";
import { projectGraph } from "./graph";
import { validateSource } from "./validation";
import type { SourceDocument } from "./types";

afterEach(cleanup);
function Harness({ initial = editorFixture, initialTab = "prompt" }: { initial?: SourceDocument; initialTab?: AgentInspectorTab }) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("intake");
  const [tab, onTabChange] = useState(initialTab);
  return <>{Object.hasOwn(document.source.participants, participantKey) && <AgentInspector document={document} onChange={onChange} participantKey={participantKey} onRenamed={onRenamed} tab={tab} onTabChange={onTabChange}
    issues={validateSource(document.source)} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: ["calendar"], toolCatalog: { ...toolCatalogFixture, tools: [...toolCatalogFixture.tools, { type: "host" as const, tool: "availability", description: "Test availability action." }, { type: "host" as const, tool: "lookup", description: "Test lookup action." }] } }} />}
    <output data-testid="source">{JSON.stringify(document.source)}</output><output data-testid="edges">{JSON.stringify(projectGraph(document).edges)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
const modelSections = () => screen.getAllByRole("region", { name: /^(Language model|Text to speech|Speech to speech|Speech to text|Output speech to text)$/ }).map((region) => region.getAttribute("aria-label"));
const switchTab = (name: string) => fireEvent.mouseDown(screen.getByRole("tab", { name }), { button: 0 });
async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}
const fill = (label: string, value: string) => fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value } });

test("agent prompt and first-message controls preserve source on load and remove mode-specific text", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake!.description = "Saved transfer context";
  render(<Harness initial={initial} />);
  expect(saved()).toEqual(initial.source);
  expect(screen.queryByRole("textbox", { name: "Description" })).not.toBeInTheDocument();
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Prompt", "Models", "Variables", "Transfers", "Tools", "Media"]);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Wait for input");
  fireEvent.keyDown(screen.getByRole("combobox", { name: "First message" }), { key: "ArrowDown" });
  expect((await screen.findAllByRole("option")).map((option) => option.textContent)).toEqual(["Wait for input", "Generated", "Fixed text"]);
  fireEvent.keyDown(screen.getByRole("listbox"), { key: "Escape" });
  fill("Prompt", "Ask one question at a time.");
  await choose("First message", "Fixed text"); fill("First message text", "Hello there.");
  expect(saved().participants.intake).toMatchObject({ prompt: "Ask one question at a time.", description: "Saved transfer context", first_message: { mode: "fixed", text: "Hello there." } });
  await choose("First message", "Generated");
  expect(saved().participants.intake.first_message).toEqual({ mode: "generated" });
  await choose("First message", "Wait for input");
  expect(saved().participants.intake).not.toHaveProperty("first_message");
  expect(saved().participants.intake.description).toBe("Saved transfer context");
});
test("only the outgoing handler defaults to Generated and can explicitly wait for input", async () => {
  const initial = structuredClone(editorFixture);
  delete initial.source.incoming_call;
  initial.source.outgoing_call = { callee: "caller", handled_by: "intake" };
  const view = render(<Harness initial={initial} />);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Generated");
  expect(saved()).toEqual(initial.source);
  await choose("First message", "Wait for input");
  expect(saved().participants.intake.first_message).toEqual({ mode: "wait_for_input" });
  await choose("First message", "Generated");
  expect(saved().participants.intake).not.toHaveProperty("first_message");
  view.unmount(); initial.source.outgoing_call.handled_by = "other";
  render(<Harness initial={initial} />);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Wait for input");
});

test("agent models show only LLM and TTS without changing an existing source on load", () => {
  render(<Harness initialTab="voice" />);
  expect(screen.getByRole("combobox", { name: "Model type" })).toHaveTextContent("LLM + Text-to-Speech");
  expect(modelSections()).toEqual(["Language model", "Text to speech"]);
  expect(saved()).toEqual(editorFixture.source);
});

test("switching to STS removes conflicting defaults while preserving other participants' effective models", async () => {
  const initial = structuredClone(editorFixture);
  const llm = { provider: "google", model: "saved-llm", provider_options: { keep: true } };
  const tts = { provider: "deepgram", model: "flux", options: { voice: "custom" } };
  const stt = { provider: "deepgram", model: "flux-general-multi" };
  initial.source.defaults = { capabilities: { model_inference: llm, text_to_speech: tts, speech_to_text: stt } };
  initial.source.participants.reviewer = { type: "agent", prompt: "Review." };
  initial.source.participants.intake!.capabilities = { speech_to_text: stt };
  render(<Harness initial={initial} initialTab="voice" />);
  await choose("Model type", "Speech-to-Speech");
  expect(modelSections()).toEqual(["Speech to speech"]);
  expect(Object.keys(saved().participants.intake.capabilities)).toEqual(["speech_to_speech"]);
  expect(saved().participants.reviewer.capabilities).toEqual({ model_inference: llm, text_to_speech: tts });
  expect(saved().defaults.capabilities).toEqual({ speech_to_text: stt });
  expect(saved().participants.caller).toEqual(initial.source.participants.caller);
  expect(saved().participants.specialist).toEqual(initial.source.participants.specialist);
  switchTab("Prompt"); switchTab("Models");
  expect(screen.getByRole("combobox", { name: "Model type" })).toHaveTextContent("Speech-to-Speech");
  await choose("Model type", "LLM + Text-to-Speech");
  expect(Object.keys(saved().participants.intake.capabilities).sort()).toEqual(["model_inference", "text_to_speech"]);
  expect(saved().participants.reviewer.capabilities).toEqual({ model_inference: llm, text_to_speech: tts });
});

test("inherited STS loads unchanged and switching to LLM preserves another agent's STS selection", async () => {
  const initial = structuredClone(editorFixture);
  const sts = { provider: "morse", model: "morse", options: { output_transcript: false } };
  const output = { provider: "morse", model: "morse" };
  initial.source.defaults = { capabilities: { speech_to_speech: sts, output_speech_to_text: output } };
  initial.source.participants.reviewer = { type: "agent", prompt: "Review." };
  render(<Harness initial={initial} initialTab="voice" />);
  expect(modelSections()).toEqual(["Speech to speech"]);
  expect(saved()).toEqual(initial.source);
  await choose("Model type", "LLM + Text-to-Speech");
  expect(Object.keys(saved().participants.intake.capabilities).sort()).toEqual(["model_inference", "text_to_speech"]);
  expect(saved().participants.reviewer.capabilities).toEqual({ speech_to_speech: sts, output_speech_to_text: output });
  expect(saved()).not.toHaveProperty("defaults");
});

test("historical agent models remain visible with every model control disabled", () => {
  const initial = structuredClone(editorFixture);
  initial.readOnly = true;
  initial.source.participants.intake!.capabilities = { speech_to_speech: { provider: "google", model: "saved-model" } };
  render(<Harness initial={initial} initialTab="voice" />);
  expect(screen.getByRole("combobox", { name: "Model type" })).toHaveTextContent("Speech-to-Speech");
  for (const control of screen.getAllByRole("combobox")) expect(control).toBeDisabled();
  expect(saved()).toEqual(initial.source);
});
test("agent renaming rewrites the entry handler and deletion leaves a required handler choice", async () => {
  render(<Harness />);
  fill("Participant key", "reception"); fireEvent.blur(screen.getByRole("textbox", { name: "Participant key" }));
  expect(saved().incoming_call.handled_by).toBe("reception");
  fireEvent.click(screen.getByRole("button", { name: "Delete participant" }));
  fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Delete participant" }));
  expect(saved().incoming_call.handled_by).toBe("");
  expect(saved().participants).not.toHaveProperty("reception");
});
test("agent voice choices preserve saved values and reset to the newly selected provider's recommendation", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake!.capabilities = { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "custom" } } };
  render(<Harness initial={initial} initialTab="voice" />);
  expect(saved()).toEqual(initial.source);
  const tts = within(screen.getByRole("region", { name: "Text to speech" }));
  fireEvent.keyDown(tts.getByRole("combobox", { name: "Provider" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "cartesia" }));
  expect(saved().participants.intake.capabilities.text_to_speech).toEqual(recommendedSelection(modelCatalogFixture, "text_to_speech", "cartesia"));
  fireEvent.keyDown(tts.getByRole("combobox", { name: "Provider" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "deepgram" }));
  expect(saved().participants.intake.capabilities.text_to_speech).toEqual({ provider: "deepgram", model: "flux", options: { voice: "hannah" } });
});
test("agent permissions and presence edit the selected participant only", async () => {
  render(<Harness initialTab="variables" />);
  await choose("appointment access for intake", "Read");
  expect(saved().participants.intake.variable_permissions).toEqual({ appointment: ["read"] });
  switchTab("Media"); await choose("Record audio", "Deny");
  expect(saved().participants.intake.while_present).toEqual({ record_audio: false });
  expect(saved().participants.specialist).toEqual(editorFixture.source.participants.specialist);
});
test("transfer search adds only eligible destinations and keeps the graph projection synchronized", () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.reviewer = { type: "agent", prompt: "Review", description: "Billing specialist" };
  initial.source.participants.visitor = { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } };
  render(<Harness initial={initial} initialTab="transfers" />);
  expect(screen.queryByText("Appointment specialist")).not.toBeInTheDocument();
  expect(within(screen.getByRole("region", { name: "Allowed destinations" })).queryByText("Human destination")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Add destination" }));
  expect(screen.queryByRole("button", { name: "Add caller" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Add visitor" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Add reviewer" })).toHaveTextContent(/^reviewer$/);
  fill("Search destinations", "billing");
  expect(screen.queryByRole("button", { name: "Add reviewer" })).not.toBeInTheDocument();
  fill("Search destinations", "review");
  fireEvent.click(screen.getByRole("button", { name: "Add reviewer" }));
  expect(screen.queryByText("Billing specialist")).not.toBeInTheDocument();
  expect(within(screen.getByRole("region", { name: "Allowed destinations" })).queryByText("Agent")).not.toBeInTheDocument();
  expect(saved().participants.intake.transfers).toEqual(["specialist", "reviewer"]);
  expect(JSON.parse(screen.getByTestId("edges").textContent!)).toContainEqual({ id: "transfer:intake:reviewer", source: "intake", target: "reviewer", locked: false });
  fireEvent.click(screen.getByRole("button", { name: "Remove transfer to specialist" }));
  expect(saved().participants.intake.transfers).toEqual(["reviewer"]);
});
test("transfer history preserves saved null until edited and clears turn count when changing mode", async () => {
  const initial = structuredClone(editorFixture);
  const intake = initial.source.participants.intake!;
  if (intake.type === "agent") intake.transfer_history = null;
  render(<Harness initial={initial} initialTab="transfers" />);
  expect(saved().participants.intake.transfer_history).toBeNull();
  await choose("Transfer history", "Last spoken turns");
  fireEvent.change(screen.getByRole("spinbutton", { name: "Spoken turns" }), { target: { value: "3" } });
  expect(saved().participants.intake.transfer_history).toEqual({ mode: "last_n_spoken", turns: 3 });
  await choose("Transfer history", "Selected history");
  expect(saved().participants.intake.transfer_history).toEqual({ mode: "selected" });
  await choose("Transfer history", "Fresh");
  expect(saved().participants.intake).not.toHaveProperty("transfer_history");
});
test("MCP tools are picked with individual modes and integration-qualified names", () => {
  render(<Harness initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  fireEvent.click(screen.getByRole("button", { name: "calendar" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "find_slots" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "Non-blocking find_slots" }));
  fireEvent.click(screen.getByRole("button", { name: "Add 1 tool" }));
  expect(saved().participants.intake.tools.calendar__find_slots).toEqual({ type: "mcp", integration: "calendar", tool: "find_slots", conversation_mode: "non_blocking" });
  const before = saved();
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  fireEvent.click(screen.getByRole("button", { name: "hangup" }));
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved()).toEqual(before);
});
test("editing a tool changes only its conversation mode and preserves its name and visibility", async () => {
  const initial = structuredClone(editorFixture);
  const intake = initial.source.participants.intake!;
  if (intake.type === "agent") intake.tools = { remote: { type: "mcp", tool: "old", integration: "calendar" }, hangup: { type: "platform", tool: "hangup" } };
  initial.source.tool_visibility_overrides = { intake: { remote: "metadata" } };
  render(<Harness initial={initial} initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Edit remote" }));
  const dialog = within(screen.getByRole("dialog"));
  expect(dialog.queryByRole("button", { name: "Change tool" })).not.toBeInTheDocument();
  expect(dialog.queryByRole("searchbox")).not.toBeInTheDocument();
  expect(dialog.getAllByRole("combobox")).toHaveLength(1);
  await choose("Conversation mode", "Non-blocking");
  fireEvent.click(screen.getByRole("button", { name: "Save tool" }));
  const expected = structuredClone(initial.source);
  if (expected.participants.intake?.type === "agent") expected.participants.intake.tools!.remote!.conversation_mode = "non_blocking";
  expect(saved()).toEqual(expected);
  expect(Object.keys(saved().participants.intake.tools)).toEqual(["remote", "hangup"]);
  fireEvent.click(screen.getByRole("button", { name: "Edit remote" }));
  await choose("Conversation mode", "Blocking");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved()).toEqual(expected);
  fireEvent.click(screen.getByRole("button", { name: "Remove remote" }));
  expect(saved().tool_visibility_overrides.intake).toEqual({});
});
test("host tools keep their registered names without exposing a key field", () => {
  render(<Harness initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  expect(screen.queryByRole("button", { name: "transfer" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "availability" })).toBeDisabled();
  fireEvent.click(screen.getByRole("button", { name: "lookup" }));
  expect(screen.queryByLabelText("Local tool key")).not.toBeInTheDocument();
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add tool" }));
  expect(saved().participants.intake.tools.lookup).toEqual({ type: "host", tool: "lookup" });
});
test("historical agent inspectors allow tab navigation and disable mutation controls", () => {
  render(<Harness initial={{ ...editorFixture, readOnly: true }} />);
  for (const name of ["Participant key", "Prompt"]) expect(screen.getByRole("textbox", { name })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Delete participant" })).toBeDisabled();
  switchTab("Transfers"); expect(screen.getByRole("button", { name: "Add destination" })).toBeDisabled();
  switchTab("Tools"); expect(screen.getByRole("button", { name: "Add tool" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Edit availability" })).toBeDisabled();
  expect(saved()).toEqual(editorFixture.source);
});

test("agent variables retain saved grants for missing sections so they can be cleared", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.call_variables = { sections: {} };
  initial.source.participants.intake = { type: "agent", prompt: "Collect information", variable_permissions: { contact: ["read"] } };
  render(<Harness initial={initial} initialTab="variables" />);
  expect(screen.getByRole("combobox", { name: "contact access for intake" })).toHaveTextContent("Read");
  await choose("contact access for intake", "No access");
  expect(saved().participants.intake.variable_permissions).toEqual({});
});


test("enabled tools show one source and name row with a tooltip only for blocking tools", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake = { type: "agent", prompt: "help", tools: {
    hangup: { type: "platform", tool: "hangup" },
    calendar__find_slots: { type: "mcp", integration: "calendar", tool: "find_slots", conversation_mode: "blocking" },
    calendar__book_slot: { type: "mcp", integration: "calendar", tool: "book_slot", conversation_mode: "non_blocking" },
  } };
  render(<Harness initial={initial} initialTab="tools" />);
  expect(screen.getByText("mcp · calendar__find_slots")).toBeVisible();
  expect(within(screen.getByRole("tabpanel", { name: "Tools" })).getAllByText(/hangup/)).toHaveLength(1);
  expect(screen.getByRole("button", { name: "Edit hangup" })).toBeEnabled();
  expect(screen.getByRole("button", { name: "Remove hangup" })).toBeEnabled();
  const indicator = screen.getByRole("button", { name: "hangup: Blocking" });
  expect(screen.getByRole("button", { name: "calendar__find_slots: Blocking" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "calendar__book_slot: Blocking" })).not.toBeInTheDocument();
  expect(screen.queryByText("Blocking")).not.toBeInTheDocument();
  expect(screen.queryByText("Non-blocking")).not.toBeInTheDocument();
  fireEvent.focus(indicator);
  expect(await screen.findByRole("tooltip")).toHaveTextContent("Blocking");
  expect(saved()).toEqual(initial.source);
});
