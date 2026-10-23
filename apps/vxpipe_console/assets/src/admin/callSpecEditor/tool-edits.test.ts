import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { addTools, setTool } from "./tool-edits";

test("editing a tool keeps its visibility when renaming and preserves other tools", () => {
  const initial = structuredClone(editorFixture);
  initial.source.tool_visibility_overrides = { intake: { availability: "full" } };
  const next = setTool(initial, "intake", "availability", "__proto__", { type: "mcp", integration: "calendar", tool: "slots", conversation_mode: "non_blocking" });
  expect(next.source.participants.intake).toMatchObject({ tools: { ["__proto__"]: { type: "mcp", integration: "calendar", tool: "slots", conversation_mode: "non_blocking" } } });
  expect(Object.hasOwn(next.source.tool_visibility_overrides!.intake!, "__proto__")).toBe(true);
  expect(next.source.tool_visibility_overrides!.intake!.__proto__).toBe("full");
  expect(next.source.tool_visibility_overrides!.intake).not.toHaveProperty("availability");
  expect(initial.source.tool_visibility_overrides!.intake).toEqual({ availability: "full" });
});
test("tool additions reject reserved keys, collisions and host aliases without changing source", () => {
  for (const name of ["transfer", "read_variables", "update_variables", "update_variable", "bad name", "availability"]) {
    expect(() => setTool(editorFixture, "intake", undefined, name, { type: "platform", tool: "hangup" })).toThrow();
  }
  expect(() => setTool(editorFixture, "intake", undefined, "alias", { type: "host", tool: "registered" })).toThrow("registered name");
  expect(() => setTool({ ...editorFixture, readOnly: true }, "intake", undefined, "hangup", { type: "platform", tool: "hangup" })).toThrow("read-only");
  expect(() => setTool(editorFixture, "intake", "missing", "hangup", { type: "platform", tool: "hangup" })).toThrow("no longer exists");
});

test("a renamed tool's visibility replaces an obsolete override at its new key", () => {
  const initial = structuredClone(editorFixture);
  initial.source.tool_visibility_overrides = { intake: { availability: "full", renamed: "hidden" } };
  const next = setTool(initial, "intake", "availability", "renamed", { type: "platform", tool: "hangup" });
  expect(next.source.tool_visibility_overrides!.intake).toEqual({ renamed: "full" });
});

test("new registrations use exact built-in names and deterministic MCP names regardless of addition order", () => {
  const choices = [
    { type: "mcp" as const, integration: "calendar", tool: "lookup" },
    { type: "mcp" as const, integration: "support", tool: "lookup" },
    { type: "platform" as const, tool: "hangup" },
  ];
  const first = addTools(editorFixture, "intake", choices);
  const reverse = addTools(editorFixture, "intake", [...choices].reverse());
  expect(first.source.participants.intake).toEqual(reverse.source.participants.intake);
  expect(first.source.participants.intake).toMatchObject({ tools: {
    calendar__lookup: { type: "mcp", integration: "calendar", tool: "lookup" },
    support__lookup: { type: "mcp", integration: "support", tool: "lookup" },
    hangup: { type: "platform", tool: "hangup" },
  } });
});
test("ambiguous, duplicate or oversized registered names fail atomically instead of inventing aliases", () => {
  expect(() => addTools(editorFixture, "intake", [
    { type: "mcp", integration: "a__b", tool: "c" },
    { type: "mcp", integration: "a", tool: "b__c" },
  ])).toThrow(/already exists/);
  expect(() => addTools(editorFixture, "intake", [
    { type: "mcp", integration: "calendar", tool: "x".repeat(128) },
  ])).toThrow(/64/);
  expect(() => addTools(editorFixture, "intake", [
    { type: "platform", tool: "hangup" }, { type: "host", tool: "availability" },
  ])).toThrow();
  expect(editorFixture.source.participants.intake).not.toHaveProperty("tools.hangup");
});

test("new MCP names fit provider constraints without rewriting the integration or remote tool name", () => {
  const tool = "x".repeat(54);
  const next = addTools(editorFixture, "intake", [{ type: "mcp", integration: "calendar", tool }]);
  expect(next.source.participants.intake).toMatchObject({ tools: { [`calendar__${tool}`]: { type: "mcp", integration: "calendar", tool } } });
  for (const selection of [
    { type: "mcp" as const, integration: "calendar", tool: "x".repeat(55) },
    { type: "mcp" as const, integration: "123calendar", tool: "find_slots" },
    { type: "mcp" as const, integration: "calendar", tool: "find--slots" },
    { type: "mcp" as const, integration: "calendar", tool: "find_slots-" },
  ]) expect(() => addTools(editorFixture, "intake", [selection])).toThrow();
});
