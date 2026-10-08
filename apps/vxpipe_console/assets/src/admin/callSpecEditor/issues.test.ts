import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { backendIssue, issueCounts, mergeIssues, retainBackendIssue } from "./issues";
import type { SourceIssue } from "./types";
const source = editorFixture.source;
const prompt: SourceIssue = { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "Prompt is required" };

test("counts place entry, settings and participant issues on their node and tab", () => {
  const issues = [prompt, { ...prompt, path: ["participants", "caller", "connection", "service"] }, { ...prompt, path: ["defaults", "capabilities", "text_to_speech"] }, { ...prompt, path: ["future_field"] }];
  expect(issueCounts(source, issues)).toEqual({ nodes: { intake: 1, $entry: 1, $settings: 1 }, tabs: { intake: { prompt: 1 }, $entry: { connection: 1 }, $settings: { defaults: 1 } } });
});
test("a repeated backend issue appears once, while distinct reasons remain", () => {
  expect(mergeIssues([prompt], { reason: prompt.reason, path: prompt.path, code: prompt.code })).toEqual([prompt]);
  expect(mergeIssues([prompt], { ...prompt, reason: "Policy rejected this prompt" })).length(2);
});
test("backend field errors survive unrelated edits and clear when their value changes", () => {
  const next = structuredClone(source); next.name = "Renamed";
  expect(retainBackendIssue(prompt, source, next)).toEqual(prompt);
  next.participants.intake = { type: "agent", prompt: "Help the caller" };
  expect(retainBackendIssue(prompt, source, next)).toBeUndefined();
});
test("editing inside an errored collection clears it, and unknown paths persist", () => {
  const next = structuredClone(source); delete next.participants.intake;
  expect(retainBackendIssue({ ...prompt, path: ["participants"] }, source, next)).toBeUndefined();
  const unknown = { ...prompt, path: ["future_field"] };
  expect(retainBackendIssue(unknown, source, next)).toEqual(unknown);
});
test("field error state excludes network, permission, conflict and malformed-request outcomes", () => {
  for (const code of ["authoring_forbidden", "revision_conflict", "call_spec_not_found", "invalid_request", "call_spec_authoring_unavailable"]) {
    expect(backendIssue(source, { status: 403, error: { ...prompt, code } })).toBeUndefined();
  }
  expect(backendIssue(source, { status: 422, error: prompt })).toEqual(prompt);
  expect(backendIssue(source, { status: 401, error: prompt })).toBeUndefined();
});
test("private-material errors never display the backend reason or source value", () => {
  const issue = backendIssue(source, { status: 422, error: { code: "private_call_spec_material", path: prompt.path, reason: "secret-value" } });
  expect(issue?.reason).toBe("Remove credentials or secrets from Agent intake › Prompt");
  expect(JSON.stringify(issue)).not.toContain("secret-value");
});
