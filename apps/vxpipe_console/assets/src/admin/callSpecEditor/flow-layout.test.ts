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

test("agent cards count declared writable variables instead of permission sections", () => {
  const document = structuredClone(editorFixture);
  document.source.call_variables = { sections: {
    contact: { schema: { type: "object", properties: { name: { type: "string" }, address: { type: "object", properties: { city: { type: "string" } } } } } },
    appointment: { schema: { type: "object", properties: { date: { type: "string" }, time: { type: "string" }, reason: { type: "string" } } } },
    routing: { schema: { type: "object", properties: { phone: { type: "string" } } } },
    empty: { schema: { type: "object" } },
  } };
  const agent = document.source.participants.intake;
  if (agent.type !== "agent") throw new Error("Expected agent fixture");
  agent.description = "Long agent description";
  agent.variable_permissions = { contact: ["read", "write"], appointment: ["write", "read"], routing: ["read"], missing: ["read", "write"], empty: ["read", "write"] };
  const before = structuredClone(document);
  const card = canvasGraph(document).nodes.find((node) => node.id === "intake")!;
  expect(card.data).toMatchObject({ label: "intake", subtitle: "", variableCount: 5 });
  expect(document).toEqual(before);
});

test("agent cards omit the prompt fallback and do not count read-only variables", () => {
  const document = structuredClone(editorFixture);
  const agent = document.source.participants.intake;
  if (agent.type !== "agent") throw new Error("Expected agent fixture");
  agent.variable_permissions = { appointment: ["read"] };
  const graph = canvasGraph(document);
  expect(graph.nodes.find((node) => node.id === "intake")?.data).toMatchObject({ subtitle: "", variableCount: 0 });
});

test("human cards show only their name whether or not a saved description exists", () => {
  const document = structuredClone(editorFixture);
  for (const description of ["Appointment specialist", undefined]) {
    document.source.participants.specialist!.description = description;
    const graph = canvasGraph(document);
    expect(graph.nodes.find((node) => node.id === "specialist")?.data).toMatchObject({ label: "specialist", subtitle: "" });
    expect(graph.nodes.find((node) => node.id === "$entry")?.data.subtitle).toBe("Incoming · caller");
  }
});
