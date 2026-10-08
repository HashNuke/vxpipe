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
    issues={validateSource(document.source)} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: {}, mcpIntegrations: ["calendar"] }} />}
    <output data-testid="source">{JSON.stringify(document.source)}</output><output data-testid="edges">{JSON.stringify(projectGraph(document).edges)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
const switchTab = (name: string) => fireEvent.mouseDown(screen.getByRole("tab", { name }), { button: 0 });
async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}
const fill = (label: string, value: string) => fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value } });

test("agent prompt and first-message controls preserve source on load and remove mode-specific text", async () => {
  render(<Harness />);
  expect(saved()).toEqual(editorFixture.source);
  expect(screen.getAllByRole("tab").map((tab) => tab.textContent)).toEqual(["Prompt", "Voice and model", "Variables", "Transfers", "Tools", "Presence"]);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Default (wait for input)");
  fill("Prompt", "Ask one question at a time."); fill("Description", "Reception agent");
  await choose("First message", "Fixed text"); fill("First message text", "Hello there.");
  expect(saved().participants.intake).toMatchObject({ prompt: "Ask one question at a time.", description: "Reception agent", first_message: { mode: "fixed", text: "Hello there." } });
  await choose("First message", "Generated");
  expect(saved().participants.intake.first_message).toEqual({ mode: "generated" });
  await choose("First message", "Default (wait for input)"); fill("Description", "");
  expect(saved().participants.intake).not.toHaveProperty("first_message");
  expect(saved().participants.intake).not.toHaveProperty("description");
});
test("only the outgoing handler shows the generated first-message default", () => {
  const initial = structuredClone(editorFixture);
  delete initial.source.incoming_call;
  initial.source.outgoing_call = { callee: "caller", handled_by: "intake" };
  const view = render(<Harness initial={initial} />);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Default (generated)");
  view.unmount(); initial.source.outgoing_call.handled_by = "other";
  render(<Harness initial={initial} />);
  expect(screen.getByRole("combobox", { name: "First message" })).toHaveTextContent("Default (wait for input)");
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
  switchTab("Presence"); await choose("Record audio", "Deny");
  expect(saved().participants.intake.while_present).toEqual({ record_audio: false });
  expect(saved().participants.specialist).toEqual(editorFixture.source.participants.specialist);
});
test("transfer search adds only eligible destinations and keeps the graph projection synchronized", () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.reviewer = { type: "agent", prompt: "Review", description: "Billing specialist" };
  initial.source.participants.visitor = { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } };
  render(<Harness initial={initial} initialTab="transfers" />);
  fireEvent.click(screen.getByRole("button", { name: "Add destination" }));
  expect(screen.queryByRole("button", { name: "Add caller" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Add visitor" })).not.toBeInTheDocument();
  fill("Search destinations", "billing");
  fireEvent.click(screen.getByRole("button", { name: "Add reviewer" }));
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
  await choose("Transfer history", "Default (fresh)");
  expect(saved().participants.intake).not.toHaveProperty("transfer_history");
});
test("the source-tool-options flow adds an MCP tool and cancellation leaves source untouched", async () => {
  render(<Harness initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  fireEvent.click(screen.getByRole("button", { name: "MCP" }));
  await choose("MCP integration", "calendar"); fill("Tool name", "find_slots");
  fireEvent.click(screen.getByRole("button", { name: "Next" }));
  fill("Local tool key", "calendar_slots"); await choose("Conversation mode", "Non-blocking");
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add tool" }));
  expect(saved().participants.intake.tools.calendar_slots).toEqual({ type: "mcp", integration: "calendar", tool: "find_slots", conversation_mode: "non_blocking" });
  const before = saved();
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  fireEvent.click(screen.getByRole("button", { name: "Platform" })); fill("Tool name", "hangup");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved()).toEqual(before);
});
test("tool editing renames visibility atomically, removes obsolete integration, and removal clears visibility", async () => {
  const initial = structuredClone(editorFixture);
  const intake = initial.source.participants.intake!;
  if (intake.type === "agent") intake.tools = { remote: { type: "mcp", tool: "old", integration: "calendar" } };
  initial.source.tool_visibility_overrides = { intake: { remote: "metadata" } };
  render(<Harness initial={initial} initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Edit remote" }));
  fireEvent.click(screen.getByRole("button", { name: "Back" }));
  fireEvent.click(screen.getByRole("button", { name: "Back" }));
  fireEvent.click(screen.getByRole("button", { name: "Platform" })); fill("Tool name", "hangup");
  fireEvent.click(screen.getByRole("button", { name: "Next" })); fill("Local tool key", "finish");
  fireEvent.click(screen.getByRole("button", { name: "Save tool" }));
  expect(saved().participants.intake.tools).toEqual({ finish: { type: "platform", tool: "hangup" } });
  expect(saved().tool_visibility_overrides.intake).toEqual({ finish: "metadata" });
  fireEvent.click(screen.getByRole("button", { name: "Remove finish" }));
  expect(saved().tool_visibility_overrides.intake).toEqual({});
});
test("reserved tool keys cannot be added, and host tools keep their registered key", () => {
  render(<Harness initialTab="tools" />);
  fireEvent.click(screen.getByRole("button", { name: "Add tool" }));
  fireEvent.click(screen.getByRole("button", { name: "Platform" })); fill("Tool name", "hangup");
  fireEvent.click(screen.getByRole("button", { name: "Next" })); fill("Local tool key", "transfer");
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add tool" }));
  expect(screen.getByRole("alert")).toHaveTextContent("reserved");
  expect(saved()).toEqual(editorFixture.source);
  fireEvent.click(screen.getByRole("button", { name: "Back" })); fireEvent.click(screen.getByRole("button", { name: "Back" }));
  fireEvent.click(screen.getByRole("button", { name: "Host" })); fill("Tool name", "lookup");
  fireEvent.click(screen.getByRole("button", { name: "Next" }));
  expect(screen.getByRole("textbox", { name: "Local tool key" })).toBeDisabled();
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add tool" }));
  expect(saved().participants.intake.tools.lookup).toEqual({ type: "host", tool: "lookup" });
});
test("historical agent inspectors allow tab navigation and disable mutation controls", () => {
  render(<Harness initial={{ ...editorFixture, readOnly: true }} />);
  for (const name of ["Participant key", "Prompt", "Description"]) expect(screen.getByRole("textbox", { name })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Delete participant" })).toBeDisabled();
  switchTab("Transfers"); expect(screen.getByRole("button", { name: "Add destination" })).toBeDisabled();
  switchTab("Tools"); expect(screen.getByRole("button", { name: "Add tool" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Edit availability" })).toBeDisabled();
  expect(saved()).toEqual(editorFixture.source);
});
