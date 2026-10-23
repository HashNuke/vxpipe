import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { EntryHandlerField } from "./entry-handler-field";
import { MediaPolicyFields } from "./media-policy-fields";
import { WaitSoundsPanel } from "./wait-sounds-panel";
import { AdvancedPanel } from "./advanced-panel";
import { editorFixture } from "./editorFixtures";
import { validateSource } from "./validation";
import { pageSnapshot } from "./page-fixtures";
import type { SourceDocument } from "./types";

afterEach(cleanup);
function Harness({ panel, initial = editorFixture, participantKey = null }: { panel: "direction" | "media" | "wait" | "advanced"; initial?: SourceDocument; participantKey?: string | null }) {
  const [document, onChange] = useState(initial);
  const props = { document, onChange, issues: validateSource(document.source) };
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
  fireEvent.change(screen.getByRole("textbox", { name: "Audio URL" }), { target: { value: "https://example.test/wait.wav" } });
  fireEvent.click(screen.getByRole("button", { name: "Use audio" }));
  expect(saved().wait_sounds.transfer_to_human).toBe("https://example.test/wait.wav");
  await choose("Call setup", "Phone ring");
  expect(saved().wait_sounds).not.toHaveProperty("call_setup");
});

test("advanced settings retain invalid numeric edits for validation and can clear optional limits", () => {
  render(<Harness panel="advanced" />);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Transfer attempt timeout (seconds)" }), { target: { value: "0.9" } });
  expect(saved().transfer_policy.attempt_timeout_ms).toBe(900);
  expect(screen.getByText("must be between 1 and 120 seconds")).toBeInTheDocument();
  fireEvent.change(screen.getByRole("spinbutton", { name: "Max call duration (seconds)" }), { target: { value: "25.6" } });
  expect(saved().limits.max_duration_ms).toBe(25600);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Max call duration (seconds)" }), { target: { value: "" } });
  expect(saved().limits).not.toHaveProperty("max_duration_ms");
});

test("stored millisecond limits display fractional seconds without changing the source", () => {
  const initial = structuredClone(editorFixture);
  initial.source.limits = { max_duration_ms: 25600 };
  initial.source.transfer_policy = { attempt_timeout_ms: 1001 };
  render(<Harness panel="advanced" initial={initial} />);
  expect(screen.getByRole("spinbutton", { name: "Max call duration (seconds)" })).toHaveValue(25.6);
  const timeout = screen.getByRole("spinbutton", { name: "Transfer attempt timeout (seconds)" });
  expect(timeout).toHaveValue(1.001);
  expect(timeout).toHaveAttribute("step", "0.001");
  expect(saved()).toEqual(initial.source);
  fireEvent.change(timeout, { target: { value: "1.001" } });
  expect(saved().transfer_policy.attempt_timeout_ms).toBe(1001);
});

test("read-only policy fields cannot mutate a historical source", () => {
  render(<Harness panel="advanced" initial={{ ...editorFixture, readOnly: true }} />);
  expect(screen.getByRole("spinbutton", { name: "Max call duration (seconds)" })).toBeDisabled();
  expect(screen.getByRole("combobox", { name: "Default tool visibility" })).toBeDisabled();
});


test.each([null, "intake"])("media edits preserve explicit empty route maps for %s", async (participantKey) => {
  const initial = structuredClone(editorFixture);
  const policy = { audio_routes: {}, transcript_routes: {} };
  if (participantKey === null) initial.source.media_policy = policy;
  else initial.source.participants[participantKey]!.while_present = policy;
  render(<Harness panel="media" participantKey={participantKey} initial={initial} />);
  expect(screen.queryByRole("combobox", { name: /routing/ })).not.toBeInTheDocument();
  await choose("Record audio", "Deny");
  const updated = saved();
  expect(participantKey === null ? updated.media_policy : updated.participants[participantKey].while_present)
    .toEqual({ ...policy, record_audio: false });
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
  source.participants.intake!.while_present = { audio_routes: { ["constructor"]: ["caller"] } };
  render(<Harness panel="media" participantKey="intake" initial={{ ...editorFixture, source }} />);
  await choose("Record audio", "Deny");
  expect(saved().participants.intake.while_present.audio_routes.constructor).toEqual(["caller"]);
});

test("Advanced exposes only call-wide visibility and preserves saved tool overrides", async () => {
  const source = structuredClone(editorFixture.source);
  const intake = source.participants.intake;
  if (intake?.type !== "agent") throw new Error("Expected fixture agent");
  intake.tools = JSON.parse('{"__proto__":{"type":"host","tool":"lookup"}}');
  source.tool_visibility_overrides = { intake: JSON.parse('{"__proto__":"metadata","transfer":"full"}') };
  render(<Harness panel="advanced" initial={{ ...editorFixture, source }} />);
  expect(screen.getAllByRole("combobox").map((control) => control.textContent)).toEqual(["Hidden"]);
  expect(screen.queryByRole("heading", { name: "intake tools" })).not.toBeInTheDocument();
  expect(saved()).toEqual(source);
  await choose("Default tool visibility", "Full");
  expect(saved().tool_visibility).toBe("full");
  expect(saved().tool_visibility_overrides).toEqual(source.tool_visibility_overrides);
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
  await choose("Default tool visibility", "Full");
  await choose("Default tool visibility", "Hidden");
  expect(saved()).not.toHaveProperty("tool_visibility");
});

test.each([null, "caller", "intake", "specialist"])("Media exposes storage permissions and preserves saved routes for %s", async (participantKey) => {
  const initial = structuredClone(editorFixture);
  initial.source.media_policy = { audio_routes: { intake: ["caller"] }, transcript_routes: { caller: ["intake"] } };
  if (participantKey !== null) initial.source.participants[participantKey]!.while_present = {
    audio_routes: { caller: ["specialist"] }, transcript_routes: { specialist: ["caller"] },
  };
  render(<Harness panel="media" participantKey={participantKey} initial={initial} />);
  expect(screen.getAllByRole("combobox")).toHaveLength(2);
  expect(screen.getByRole("combobox", { name: "Record audio" })).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Save transcripts" })).toBeInTheDocument();
  expect(screen.queryByRole("checkbox")).not.toBeInTheDocument();
  expect(saved()).toEqual(initial.source);

  await choose("Record audio", "Deny");
  await choose("Save transcripts", "Deny");
  const expected = structuredClone(initial.source);
  const policy = participantKey === null ? expected.media_policy! : expected.participants[participantKey]!.while_present!;
  policy.record_audio = false;
  policy.save_transcripts = false;
  expect(saved()).toEqual(expected);

  const reset = participantKey === null ? "Allow" : "Inherit";
  await choose("Record audio", reset);
  await choose("Save transcripts", reset);
  if (participantKey === null) {
    policy.record_audio = true;
    policy.save_transcripts = true;
  } else {
    delete policy.record_audio;
    delete policy.save_transcripts;
  }
  expect(saved()).toEqual(expected);
});


test("wait sound URL edits are validated and only applied on confirmation", async () => {
  render(<Harness panel="wait" />);
  await choose("Transfer to agent", "Audio URL");
  expect(saved()).toEqual(editorFixture.source);
  fireEvent.change(screen.getByRole("textbox", { name: "Audio URL" }), { target: { value: "file:///wait.wav" } });
  fireEvent.click(screen.getByRole("button", { name: "Use audio" }));
  expect(screen.getByRole("alert")).toHaveTextContent("HTTP(S)");
  expect(saved()).toEqual(editorFixture.source);
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  await choose("Transfer to agent", "Audio URL");
  fireEvent.change(screen.getByRole("textbox", { name: "Audio URL" }), { target: { value: "  https://example.test/music.wav  " } });
  fireEvent.click(screen.getByRole("button", { name: "Use audio" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  expect(saved().wait_sounds.transfer_to_agent).toBe("https://example.test/music.wav");
  fireEvent.click(screen.getByRole("button", { name: "Edit Transfer to agent audio URL" }));
  expect(screen.getByRole("textbox", { name: "Audio URL" })).toHaveValue("https://example.test/music.wav");
  fireEvent.change(screen.getByRole("textbox", { name: "Audio URL" }), { target: { value: "https://example.test/changed.wav" } });
  fireEvent.click(screen.getByRole("button", { name: "Close" }));
  expect(saved().wait_sounds.transfer_to_agent).toBe("https://example.test/music.wav");
});

test("historical wait sound choices cannot be edited", () => {
  render(<Harness panel="wait" initial={{ ...editorFixture, readOnly: true }} />);
  for (const control of screen.getAllByRole("combobox")) expect(control).toBeDisabled();
});
