import { expect, test } from "vitest";
import { parseSource } from "./source";
import { addParticipant, removeParticipant, renameParticipant, setTransfer } from "./participants";

function document() {
  return parseSource(JSON.stringify({schema_version: "20261004.01", incoming_call: {caller: "caller", handled_by: "assistant"}, participants: {
    caller: {type: "human", connection: {service: "web", mode: "receive", admission: "start_call"}},
    assistant: {type: "agent", prompt: "Keep assistant in this literal prompt.", transfers: ["human"], while_present: {audio_routes: {assistant: ["caller"]}}},
    human: {type: "human", connection: {service: "web", mode: "receive", admission: "transfer"}},
    observer: {type: "agent", prompt: "Observe.", transfers: ["assistant"]},
  }, media_policy: {audio_routes: {caller: ["assistant"], assistant: ["human"]}, transcript_routes: {assistant: ["observer"]}}, tool_visibility_overrides: {assistant: {transfer: "full"}}}));
}

test("renaming rewrites every participant reference and preserves literal text", () => {
  const original = document();
  const renamed = renameParticipant(original, "assistant", "reception");
  expect(renamed.source.incoming_call?.handled_by).toBe("reception");
  expect(renamed.source.participants.assistant).toBeUndefined();
  expect(renamed.source.participants.reception).toMatchObject({prompt: "Keep assistant in this literal prompt.", while_present: {audio_routes: {reception: ["caller"]}}});
  expect(renamed.source.participants.observer).toMatchObject({transfers: ["reception"]});
  expect(renamed.source.media_policy).toEqual({audio_routes: {caller: ["reception"], reception: ["human"]}, transcript_routes: {reception: ["observer"]}});
  expect(renamed.source.tool_visibility_overrides).toEqual({reception: {transfer: "full"}});
  expect(original).toEqual(document());
  expect(renameParticipant(original, "caller", "customer").source.incoming_call?.caller).toBe("customer");
});

test("participant names are validated and cannot overwrite another participant", () => {
  for (const key of ["", "bad name", "human"]) expect(() => renameParticipant(document(), "assistant", key)).toThrow();
  expect(() => renameParticipant(document(), "missing", "new")).toThrow();
  const renamed = renameParticipant(document(), "assistant", "__proto__");
  expect(Object.hasOwn(renamed.source.participants, "__proto__")).toBe(true);
  expect(renamed.source.incoming_call?.handled_by).toBe("__proto__");
});

test("removing a destination cleans transfers and routes; removing the handler leaves a required choice", () => {
  const removed = removeParticipant(document(), "assistant");
  expect(removed.source.incoming_call?.handled_by).toBe("");
  expect(removed.source.participants.observer).toMatchObject({transfers: []});
  expect(removed.source.media_policy?.audio_routes).toEqual({caller: []});
  expect(removed.source.tool_visibility_overrides).toEqual({});
  expect(() => removeParticipant(document(), "caller")).toThrow("entry");
});

test("adding participants and changing transfers keeps a single edge and generated visibility valid", () => {
  let edited = addParticipant(document(), "specialist", "agent");
  edited = setTransfer(edited, "assistant", "specialist", true);
  edited = setTransfer(edited, "assistant", "specialist", true);
  expect(edited.source.participants.assistant).toMatchObject({transfers: ["human", "specialist"]});
  edited = setTransfer(edited, "assistant", "human", false);
  edited = setTransfer(edited, "assistant", "specialist", false);
  expect(edited.source.tool_visibility_overrides?.assistant).toEqual({});
  expect(() => setTransfer(edited, "human", "specialist", true)).toThrow();
  expect(() => setTransfer(edited, "assistant", "assistant", true)).toThrow();
  expect(addParticipant(document(), "support", "human").source.participants.support).toMatchObject({type: "human", connection: {service: "web", mode: "receive", admission: "transfer"}});
});

test("historical documents cannot be edited even if a caller changes the read-only flag", () => {
  const old = {...document(), readOnly: false};
  old.source.schema_version = "20260915.01";
  expect(() => addParticipant(old, "new", "agent")).toThrow("read-only");
});

test("new human transfers require transfer admission, while stale references can still be removed", () => {
  const source = document();
  source.source.participants.human = {type: "human", connection: {service: "web", mode: "receive", admission: "start_call"}};
  expect(() => setTransfer(source, "assistant", "human", true)).toThrow("transfer");
  expect(setTransfer(source, "assistant", "human", false).source.participants.assistant).toMatchObject({transfers: []});
});
