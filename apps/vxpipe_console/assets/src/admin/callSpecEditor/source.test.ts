/// <reference types="vite/client" />
import { expect, test } from "vitest";
import { parseSource, serializeSource } from "./source";
import { entryUpgradeNotice, upgradeEntrySettings } from "./entry-schema-upgrade";
import { projectGraph } from "./graph";

const examples = import.meta.glob<string>("../../../../../../examples/call-specs/*.json", {
  eager: true, query: "?raw", import: "default",
});

for (const [name, source] of Object.entries(examples)) {
  test(`${name} round-trips through the canvas without changing its JSON value`, () => {
    const document = parseSource(source);
    const graph = projectGraph(document);
    expect(document.readOnly).toBe(false);
    expect(graph.nodes.length).toBeGreaterThan(1);
    expect(JSON.parse(serializeSource(document))).toEqual(JSON.parse(source));
    expect(serializeSource(document)).not.toContain('"position"');
  });
}

test("historical source opens read-only without migration", () => {
  const source = {schema_version: "20260915.01", entry_caller: "caller", entry_receiver: "assistant", participants: {
    caller: {type: "human", connection: {service: "web", mode: "receive", admission: "start_call"}},
    assistant: {type: "agent", prompt: "Help."},
  }};
  const document = parseSource(JSON.stringify(source));
  expect(document.readOnly).toBe(true);
  expect(document.notice).toContain("20260915.01");
  expect(JSON.parse(serializeSource(document))).toEqual(source);
  expect(projectGraph(document).nodes[0]).toMatchObject({kind: "entry", participantKey: "caller"});
});

test("graph order follows transfers with entry, agents, then human destinations", () => {
  const document = parseSource(JSON.stringify({schema_version: "20261004.01", incoming_call: {caller: "caller", handled_by: "reception"}, participants: {
    caller: {type: "human", connection: {service: "web", mode: "receive", admission: "start_call"}},
    human: {type: "human", connection: {service: "phone", mode: "dial", number: "+15550001000"}},
    unrelated: {type: "agent", prompt: "Wait."},
    specialist: {type: "agent", prompt: "Help.", transfers: ["human"]},
    reception: {type: "agent", prompt: "Welcome.", transfers: ["specialist", "human"]},
  }}));
  const graph = projectGraph(document);
  expect(graph.nodes.map((node) => node.participantKey)).toEqual(["caller", "reception", "specialist", "unrelated", "human"]);
  expect(graph.edges.map((edge) => [edge.source, edge.target])).toEqual([
    ["$entry", "reception"], ["reception", "specialist"], ["reception", "human"], ["specialist", "human"],
  ]);
  expect(projectGraph(document)).toEqual(graph);
  expect(graph.nodes[0]?.locked).toBe(true);
});

test("unknown versions and non-document JSON do not get silently normalized", () => {
  for (const value of ["null", "[]", '{"schema_version":"future","participants":{}}']) {
    expect(() => parseSource(value)).toThrow();
  }
});

test("upgrading a directional draft requires an explicit action and preserves the original revision", () => {
  const previous = parseSource(JSON.stringify({schema_version: "20261004.01", incoming_call: { caller: "caller", handled_by: "assistant" }, participants: {
    caller: {type: "human", connection: {service:"web",mode:"receive",admission:"start_call"}, while_present:{record_audio:false}, capabilities:{speech_to_text:{provider:"morse",model:"morse"}}},
    assistant: {type:"agent",prompt:"Help."}}, opening_audio:{type:"text",text:"Hi",text_to_speech:{provider:"morse",model:"morse"}}}));
  const notice = entryUpgradeNotice(previous.source);
  expect(notice).toMatch(/media/i);
  expect(notice).toMatch(/transcription/i);
  expect(notice).toMatch(/voice/i);
  const next = upgradeEntrySettings(previous.source);
  expect(next.source.participants.caller).not.toHaveProperty("while_present");
  expect(next.source.participants.caller).not.toHaveProperty("capabilities");
  expect(next.source.opening_audio).toEqual({type:"text",text:"Hi"});
  expect(next.source.schema_version).toBe("20261125.01");
  expect(previous.source.participants.caller?.while_present).toEqual({record_audio:false});
});
