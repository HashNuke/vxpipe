import { expect, test } from "vitest";
import fixture from "../../../../../../examples/contracts/call-spec-editor-validation.json";
import { validateSource } from "./validation";

type Change = { path: string[]; value?: unknown; delete?: boolean; repeat?: number };
function changed(base: unknown, changes: Change[]) {
  const source = structuredClone(base) as Record<string, unknown>;
  for (const change of changes) {
    let owner = source;
    for (const key of change.path.slice(0, -1)) owner = (owner[key] ??= {}) as Record<string, unknown>;
    const key = change.path.at(-1)!;
    if (change.delete) delete owner[key];
    else owner[key] = change.repeat ? String(change.value).repeat(change.repeat) : structuredClone(change.value);
  }
  return source;
}

for (const scenario of fixture.cases) {
  test(`backend path contract: ${scenario.name}`, () => {
    const source = changed(fixture.bases[scenario.base as keyof typeof fixture.bases], scenario.changes);
    const original = structuredClone(source);
    const issues = validateSource(source);
    if (scenario.expected_path === null) expect(issues).toEqual([]);
    else expect(issues).toEqual(expect.arrayContaining([expect.objectContaining({ code: "invalid_call_spec", path: scenario.expected_path })]));
    expect(source).toEqual(original);
  });
}

test("client validation accumulates independent errors without echoing submitted values", () => {
  const source = changed(fixture.bases.incoming, [{path: ["participants", "assistant", "prompt"], value: ""}, {path: ["name"], value: "private-secret".repeat(100)}]);
  const issues = validateSource(source);
  expect(issues.map((issue) => issue.path)).toEqual(expect.arrayContaining([["name"], ["participants", "assistant", "prompt"]]));
  expect(JSON.stringify(issues)).not.toContain("private-secret");
});
