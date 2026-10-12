import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { EntryHandlerField } from "./entry-handler-field";
import { MediaPolicyFields } from "./media-policy-fields";
import { WaitSoundsPanel } from "./wait-sounds-panel";
import { AdvancedPanel } from "./advanced-panel";
import { editorFixture } from "./editorFixtures";
import { pageSnapshot } from "./page-fixtures";
import type { SourceDocument } from "./types";

afterEach(cleanup);
function Harness({ panel, initial = editorFixture, participantKey = null }: { panel: "direction" | "media" | "wait" | "advanced"; initial?: SourceDocument; participantKey?: string | null }) {
  const [document, onChange] = useState(initial);
  const props = { document, onChange };
  return <>{panel === "direction" ? <EntryHandlerField {...props} />
    : panel === "media" ? <MediaPolicyFields {...props} participantKey={participantKey} />
    : panel === "wait" ? <WaitSoundsPanel {...props} /> : <AdvancedPanel {...props} />}
    <output data-testid="source">{JSON.stringify(document.source)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);

async function choose(label: string, option: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: option }));
}

test.each(["default", "outgoing"] as const)("entry handler field leaves participant identity on its card: %s", (scenario) => {
  const initial = pageSnapshot(scenario).document;
  render(<Harness panel="direction" initial={initial} />);
  expect(screen.queryByRole("combobox", { name: /^(Caller|Callee)$/ })).not.toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Handled by" })).toHaveTextContent("intake");
  expect(screen.queryByRole("button", { name: /Switch to/ })).not.toBeInTheDocument();
  expect(saved()).toEqual(initial.source);
});

test("media controls preserve omitted defaults, explicit denials and other routes", async () => {
  render(<Harness panel="media" initial={{ ...editorFixture, source: { ...editorFixture.source, media_policy: { audio_routes: { intake: ["caller"] }, save_transcripts: false } } }} />);
  await choose("Record audio", "Allow");
  expect(saved().media_policy).not.toHaveProperty("record_audio");
  await choose("Record audio", "Deny");
  await choose("Record audio", "Allow");
  expect(saved().media_policy).toEqual({ audio_routes: { intake: ["caller"] }, save_transcripts: false, record_audio: true });
  expect(screen.queryByRole("combobox", { name: "Audio routing" })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "Transcript routing" })).not.toBeInTheDocument();
});

test("wait sounds distinguish default, explicit silence and an audio URL", async () => {
  render(<Harness panel="wait" />);
  await choose("Call setup", "Silence");
  expect(saved().wait_sounds.call_setup).toBeNull();
  await choose("Transfer to human", "Audio URL");
  fireEvent.change(screen.getByRole("textbox", { name: "Transfer to human URL" }), { target: { value: "https://example.test/wait.wav" } });
  expect(saved().wait_sounds.transfer_to_human).toBe("https://example.test/wait.wav");
  await choose("Call setup", "Phone ring");
  expect(saved().wait_sounds).not.toHaveProperty("call_setup");
});

test("advanced settings retain invalid numeric edits for validation and can clear optional limits", () => {
  render(<Harness panel="advanced" />);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Transfer attempt timeout (ms)" }), { target: { value: "900" } });
  expect(saved().transfer_policy.attempt_timeout_ms).toBe(900);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Maximum call duration (ms)" }), { target: { value: "600000" } });
  expect(saved().limits.max_duration_ms).toBe(600000);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Maximum call duration (ms)" }), { target: { value: "" } });
  expect(saved().limits).not.toHaveProperty("max_duration_ms");
});

test("read-only policy fields cannot mutate a historical source", () => {
  render(<Harness panel="advanced" initial={{ ...editorFixture, readOnly: true }} />);
  expect(screen.getByRole("spinbutton", { name: "Maximum call duration (ms)" })).toBeDisabled();
  expect(screen.getByRole("combobox", { name: "Default tool visibility" })).toBeDisabled();
});


test("an explicit empty route map means nobody, and remains explicit after another edit", async () => {
  const initial = structuredClone(editorFixture);
  initial.source.participants.intake!.while_present = { audio_routes: {} };
  render(<Harness panel="media" participantKey="intake" initial={initial} />);
  expect(screen.getByRole("combobox", { name: "Audio routing" })).toHaveTextContent("Restricted");
  expect(screen.getByRole("combobox", { name: "Audio from intake" })).toHaveTextContent("Nobody");
  await choose("Record audio", "Deny");
  expect(saved().participants.intake.while_present.audio_routes).toEqual({});
});

test("whole-policy silence is displayed and preserved for unedited wait slots", async () => {
  render(<Harness panel="wait" initial={{ ...editorFixture, source: { ...editorFixture.source, wait_sounds: null } }} />);
  expect(screen.getByRole("combobox", { name: "Call setup" })).toHaveTextContent("Silence");
  await choose("Call setup", "Phone ring");
  expect(saved().wait_sounds).toEqual({ transfer_to_agent: null, transfer_to_human: null, transfer_joining: null });
});

test("prototype-shaped participant identifiers remain ordinary route keys", async () => {
  const source = structuredClone(editorFixture.source);
  source.participants = { ...source.participants, ["constructor"]: { type: "human" as const, connection: { service: "web", mode: "receive" as const, admission: "transfer" as const } } };
  source.participants.intake!.while_present = { audio_routes: {} };
  render(<Harness panel="media" participantKey="intake" initial={{ ...editorFixture, source }} />);
  expect(screen.getByRole("combobox", { name: "Audio from constructor" })).toHaveTextContent("Nobody");
  fireEvent.click(screen.getByRole("checkbox", { name: "Audio from constructor to caller" }));
  expect(saved().participants.intake.while_present.audio_routes.constructor).toEqual(["caller"]);
});

test("prototype-shaped tool keys retain an explicit visibility override", async () => {
  const source = structuredClone(editorFixture.source);
  const intake = source.participants.intake;
  if (intake?.type !== "agent") throw new Error("Expected fixture agent");
  intake.tools = JSON.parse('{"__proto__":{"type":"host","tool":"lookup"}}');
  render(<Harness panel="advanced" initial={{ ...editorFixture, source }} />);
  await choose("intake / __proto__ visibility", "Metadata");
  expect(Object.hasOwn(saved().tool_visibility_overrides.intake, "__proto__")).toBe(true);
  expect(saved().tool_visibility_overrides.intake.__proto__).toBe("metadata");
});

test("omitted settings display the concrete runtime choices without changing source", async () => {
  render(<Harness panel="media" />);
  expect(screen.getByRole("combobox", { name: "Record audio" })).toHaveTextContent("Allow");
  expect(screen.getByRole("combobox", { name: "Save transcripts" })).toHaveTextContent("Allow");
  expect(screen.queryByRole("combobox", { name: "Audio routing" })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "Transcript routing" })).not.toBeInTheDocument();
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Record audio" }), { key: "ArrowDown" });
  expect((await screen.findAllByRole("option")).map(item => item.textContent)).toEqual(["Allow", "Deny"]);
  expect(saved()).toEqual(editorFixture.source);
});
test("omitted wait sounds show their slot-specific audio choices", () => {
  render(<Harness panel="wait" />);
  expect(screen.getByRole("combobox", { name: "Call setup" })).toHaveTextContent("Phone ring");
  expect(screen.getByRole("combobox", { name: "Transfer to human" })).toHaveTextContent("Phone ring");
  expect(screen.getByRole("combobox", { name: "Transfer to agent" })).toHaveTextContent("Cafe bossa");
  expect(screen.getByRole("combobox", { name: "Transfer joining" })).toHaveTextContent("Cafe bossa");
  expect(saved()).toEqual(editorFixture.source);
});
test("omitted tool visibility displays Hidden and can restore the call-wide level", async () => {
  render(<Harness panel="advanced" />);
  expect(screen.getByRole("combobox", { name: "Default tool visibility" })).toHaveTextContent("Hidden");
  await choose("intake / transfer visibility", "Full");
  await choose("intake / transfer visibility", "Hidden");
  expect(saved().tool_visibility_overrides.intake).not.toHaveProperty("transfer");
});

test.each(["intake", "specialist"])("both routing controls edit only participant %s", async (participantKey) => {
  const initial = structuredClone(editorFixture);
  initial.source.media_policy = { audio_routes: { intake: ["caller"] }, transcript_routes: { caller: ["intake"] } };
  render(<Harness panel="media" participantKey={participantKey} initial={initial} />);
  for (const label of ["Audio routing", "Transcript routing"]) {
    expect(screen.getByRole("combobox", { name: label })).toHaveTextContent("Inherit");
    await choose(label, "Restricted");
  }
  await choose("Audio from intake", "All other participants");
  await choose("Transcripts from caller", "All other participants");
  expect(saved().participants[participantKey].while_present).toEqual({
    audio_routes: { intake: ["caller", "specialist"] },
    transcript_routes: { caller: ["intake", "specialist"] }
  });
  expect(saved().media_policy).toEqual(initial.source.media_policy);
  const otherKey = participantKey === "intake" ? "specialist" : "intake";
  expect(saved().participants[otherKey]).toEqual(initial.source.participants[otherKey]);
});
