import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { canvasGraph, canConnectParticipants } from "./flow-layout";

test("canvas derives participant cards and locked entry edge without changing the source", () => {
  const before = JSON.stringify(editorFixture);
  const graph = canvasGraph(editorFixture, "intake", { intake: 2 });
  expect(graph.nodes.map((node) => node.id)).toEqual(["$entry", "intake", "specialist"]);
  expect(graph.nodes.find((node) => node.id === "intake")?.data).toMatchObject({ label: "intake", issueCount: 2, toolCount: 1, variableCount: 1 });
  expect(graph.nodes.find((node) => node.id === "intake")?.selected).toBe(true);
  expect(graph.edges.find((edge) => edge.id === "$entry-edge")).toMatchObject({ deletable: false, reconnectable: false });
  expect(graph.nodes.every((node) => node.deletable === false)).toBe(true);
  expect(JSON.stringify(editorFixture)).toBe(before);
});

test("drawing permits agent transfers to existing other participants only", () => {
  expect(canConnectParticipants(editorFixture, "intake", "specialist")).toBe(true);
  expect(canConnectParticipants(editorFixture, "intake", "$entry")).toBe(false);
  for (const [source, target] of [["$entry", "intake"], ["specialist", "intake"], ["intake", "intake"], ["intake", "missing"]]) {
    expect(canConnectParticipants(editorFixture, source!, target!)).toBe(false);
  }
  expect(canConnectParticipants({ ...editorFixture, readOnly: true }, "intake", "specialist")).toBe(false);
});

test("transfer drawing rejects humans without transfer admission and accepts implicit phone transfer admission", () => {
  const document = structuredClone(editorFixture);
  document.source.participants.visitor = { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } };
  expect(canConnectParticipants(document, "intake", "visitor")).toBe(false);
  expect(canConnectParticipants(document, "intake", "caller")).toBe(false);
  document.source.participants.visitor.connection = { service: "phone", mode: "dial", number: "+15550001000" };
  expect(canConnectParticipants(document, "intake", "visitor")).toBe(true);
});
