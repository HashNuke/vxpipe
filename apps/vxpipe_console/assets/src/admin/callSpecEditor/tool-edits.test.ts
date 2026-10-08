import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { setTool } from "./tool-edits";

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
