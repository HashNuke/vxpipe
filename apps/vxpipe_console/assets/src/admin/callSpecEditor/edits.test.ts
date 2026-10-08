import { expect, test } from "vitest";
import { parseSource } from "./source";
import { setCapability, setFirstMessage, setMediaPolicy, setTools, setWaitSounds, switchDirection } from "./edits";

function document() {
  return parseSource(JSON.stringify({ schema_version: "20261004.01", incoming_call: { caller: "caller", handled_by: "assistant" }, participants: {
    caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
    assistant: { type: "agent", prompt: "Help.", first_message: { mode: "fixed", text: "Hello" } },
  }, defaults: { capabilities: { model_inference: { provider: "google", model: "original" } } } }));
}

test("switching direction retains the entry key and explicit first message; requires a phone service for outgoing", () => {
  const original = document();
  const outgoing = switchDirection(original, "outgoing", "office");
  expect(outgoing.source.incoming_call).toBeUndefined();
  expect(outgoing.source.outgoing_call).toEqual({ callee: "caller", handled_by: "assistant" });
  expect(outgoing.source.participants.caller).toMatchObject({ connection: { service: "office", mode: "dial", admission: "start_call" } });
  expect(outgoing.source.participants.assistant).toEqual(original.source.participants.assistant);
  expect(switchDirection(outgoing, "incoming")).toEqual(original);
  expect(() => switchDirection(original, "outgoing", "web")).toThrow("phone service");
  expect(() => switchDirection(original, "outgoing")).toThrow("phone service");
  expect(original).toEqual(document());
});

test("capability overrides can be set and cleared without changing inherited selections", () => {
  const original = document();
  const selection = { provider: "deepgram", model: "flux", options: { voice: "hannah" } };
  const edited = setCapability(original, "assistant", "text_to_speech", selection);
  selection.options.voice = "changed outside editor";
  expect(edited.source.participants.assistant?.capabilities?.text_to_speech?.options?.voice).toBe("hannah");
  expect(edited.source.defaults).toEqual(original.source.defaults);
  expect(setCapability(edited, "assistant", "text_to_speech", undefined)).toEqual(original);
  expect(setCapability(original, null, "model_inference", undefined).source.defaults).toBeUndefined();
});

test("field operations distinguish omission from explicit silence and clean removed tool visibility", () => {
  let edited = document();
  edited.source.tool_visibility_overrides = { assistant: { lookup: "full", other: "hidden" } };
  edited = setTools(edited, "assistant", { lookup: { type: "host", tool: "lookup" } });
  edited = setTools(edited, "assistant", {});
  expect(edited.source.tool_visibility_overrides?.assistant).toEqual({ other: "hidden" });
  edited = setFirstMessage(edited, "assistant", undefined);
  expect(edited.source.participants.assistant).not.toHaveProperty("first_message");
  expect(() => setFirstMessage(edited, "caller", { mode: "generated" })).toThrow("agent");
  edited = setWaitSounds(edited, null);
  expect(edited.source.wait_sounds).toBeNull();
  edited = setWaitSounds(edited, { call_setup: null });
  expect(edited.source.wait_sounds).toEqual({ call_setup: null });
  edited = setWaitSounds(edited, undefined);
  expect(edited.source).not.toHaveProperty("wait_sounds");
  edited = setMediaPolicy(edited, "caller", { record_audio: false });
  expect(edited.source.participants.caller?.while_present).toEqual({ record_audio: false });
  expect(edited.source.media_policy).toBeUndefined();
});
