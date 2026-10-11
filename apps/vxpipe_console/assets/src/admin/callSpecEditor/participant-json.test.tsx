import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { AgentInspector } from "./agent-inspector";
import { HumanInspector } from "./human-inspector";
import { InboundInspector } from "./inbound-inspector";
import { editorFixture } from "./editorFixtures";
import { parseSourceJson } from "./source-json";
import { applyJson } from "./json-edits";
import { serializeSource } from "./source";
import type { SourceDocument } from "./types";

afterEach(cleanup);
function Harness({ kind = "agent", initial = editorFixture }: { kind?: "agent" | "human" | "entry"; initial?: SourceDocument }) {
  const [document, onChange] = useState(() => structuredClone(initial));
  const props = { document, onChange, catalog: modelCatalogFixture, lookups: { telephonyServices: [], credentialNames: {}, mcpIntegrations: [] } };
  return <div style={{ height: 800 }}>{kind === "agent" ? <AgentInspector {...props} participantKey="intake" /> : kind === "human" ? <HumanInspector {...props} participantKey="specialist" /> : <InboundInspector {...props} />}<output data-testid="source">{serializeSource(document)}</output></div>;
}
const click = (name: string) => fireEvent.click(screen.getByRole("button", { name }));
const fill = (value: string) => fireEvent.change(screen.getByRole("textbox", { name: "Participant JSON" }), { target: { value } });
const source = () => parseSourceJson(screen.getByTestId("source").textContent!) as SourceDocument["source"];

test("participant JSON edits only that participant and preserves exact option integers", () => {
  render(<Harness />); click("Participant JSON");
  const participant = { ...editorFixture.source.participants.intake, prompt: "Updated prompt", capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash", options: { limit: "EXACT" }, provider_options: { nested: [true, null] } } } };
  fill(JSON.stringify(participant).replace('"EXACT"', '9007199254740993'));
  expect(source()).toEqual(editorFixture.source);
  click("Apply JSON");
  expect(source()).toEqual({ ...editorFixture.source, participants: { ...editorFixture.source.participants, intake: { ...participant, capabilities: { ...participant.capabilities, model_inference: { ...participant.capabilities.model_inference, options: { limit: 9007199254740993n } } } } } });
  click("Participant JSON");
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveValue("Updated prompt");
});

test("invalid JSON and invalid participant fields retain source and explain the problem", () => {
  render(<Harness />); click("Participant JSON"); fill('{'); click("Apply JSON");
  expect(screen.getByRole("alert")).toHaveTextContent("valid JSON");
  fill(JSON.stringify({ type: "agent", prompt: "" })); click("Apply JSON");
  expect(screen.getByRole("alert")).toHaveTextContent("prompt");
  expect(source()).toEqual(editorFixture.source);
  click("Discard JSON changes");
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveValue(JSON.stringify(editorFixture.source.participants.intake, null, 2));
});

test.each(["human", "entry"] as const)("%s sidebar provides participant JSON and a Media tab", (kind) => {
  render(<Harness kind={kind} />);
  expect(screen.getByRole("tab", { name: "Media" })).toBeInTheDocument();
  click("Participant JSON");
  const key = kind === "human" ? "specialist" : "caller";
  const next = { ...editorFixture.source.participants[key], description: "JSON description" };
  fill(JSON.stringify(next)); click("Apply JSON");
  expect(source().participants[key]).toEqual(next);
});

test("historical participant JSON is viewable and read-only", () => {
  render(<Harness initial={{ ...editorFixture, readOnly: true }} />); click("Participant JSON");
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveAttribute("readonly");
  expect(screen.queryByRole("button", { name: "Apply JSON" })).not.toBeInTheDocument();
});


test("full JSON cannot change the chosen call direction", () => {
  const outgoing = structuredClone(editorFixture);
  delete outgoing.source.incoming_call;
  outgoing.source.outgoing_call = { callee: "caller", handled_by: "intake" };
  outgoing.source.participants.caller = { type: "human", connection: { service: "office", mode: "dial", admission: "start_call" } };
  expect(() => applyJson(editorFixture, serializeSource(outgoing))).toThrow("Call direction cannot be changed");
  expect(() => applyJson(outgoing, serializeSource(editorFixture))).toThrow("Call direction cannot be changed");
});
