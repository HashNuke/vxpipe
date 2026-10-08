import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { createEditorState, editorReducer, isDirty } from "./editor-state";

const document = structuredClone(editorFixture);
document.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" } } };
const saved = () => createEditorState({ document, saved: { callSpecId: "appointments", revision: 3, publishedRevision: 2 } });
const editName = (state: ReturnType<typeof saved>, name: string) => editorReducer(state, { type: "edit", document: { ...state.document, source: { ...state.document.source, name } } });

test("new documents are unsaved; loaded sources keep their exact baseline", () => {
  expect(isDirty(createEditorState({ document }))).toBe(true);
  const state = saved();
  expect(isDirty(state)).toBe(false);
  expect(state.document).toEqual(document);
  expect(isDirty(editName(state, "Changed"))).toBe(true);
  expect(isDirty(editName(editName(state, "Changed"), document.source.name!))).toBe(false);
});

test("saving snapshots the submitted source and preserves later edits on success", () => {
  const state = editorReducer(editName(saved(), "Submitted"), { type: "start", action: "save" });
  expect(state.pending).toMatchObject({ id: 1, action: "save", callSpecId: "appointments", source: { name: "Submitted" } });
  const edited = editName(state, "Still editing");
  const completed = editorReducer(edited, { type: "complete", id: 1, result: { status: 201, revision: 4 } });
  expect(completed.document.source.name).toBe("Still editing");
  expect(completed.saved?.revision).toBe(4);
  expect(completed.saved?.publishedRevision).toBe(2);
  expect(completed.pending).toBeUndefined();
  expect(isDirty(completed)).toBe(true);
  expect(isDirty(editName(completed, "Submitted"))).toBe(false);
  expect(completed.feedback.toast?.message).toBe("Saved as revision 4");
});

test("a first save records the server ID and makes an unchanged new spec publishable", () => {
  const pending = editorReducer(createEditorState({ document }), { type: "start", action: "save" });
  const complete = editorReducer(pending, { type: "complete", id: 1, result: { status: 201, callSpecId: "new-id", revision: 1 } });
  expect(isDirty(complete)).toBe(false);
  expect(editorReducer(complete, { type: "start", action: "publish" }).pending).toMatchObject({ callSpecId: "new-id", revision: 1, action: "publish" });
});

test("client errors block requests and editing only updates validation, without a new toast", () => {
  const invalid = editName(saved(), "x".repeat(257));
  expect(invalid.clientIssues).toHaveLength(1);
  expect(invalid.feedback.toast).toBeNull();
  const blocked = editorReducer(invalid, { type: "start", action: "save" });
  expect(blocked.pending).toBeUndefined();
  expect(blocked.feedback.toast?.message).toBe("Fix 1 issue before saving");
  expect(editName(blocked, "Fixed").clientIssues).toEqual([]);
});

test("pending actions, dirty publication and read-only documents cannot start requests", () => {
  const state = saved();
  const saving = editorReducer(state, { type: "start", action: "save" });
  expect(editorReducer(saving, { type: "start", action: "publish" })).toBe(saving);
  expect(editorReducer(editName(state, "Dirty"), { type: "start", action: "publish" }).pending).toBeUndefined();
  const readOnly = createEditorState({ document: { ...document, readOnly: true } });
  expect(editName(readOnly, "Forbidden")).toBe(readOnly);
  expect(editorReducer(readOnly, { type: "start", action: "save" })).toBe(readOnly);
});

test("failures retain draft and baseline; permission gates survive further edits", () => {
  const edited = editName(saved(), "Keep me");
  const saving = editorReducer(edited, { type: "start", action: "save" });
  const failed = editorReducer(saving, { type: "complete", id: 1, result: { status: 403, error: { code: "authoring_forbidden" } } });
  expect(failed.document).toEqual(edited.document);
  expect(failed.saved).toEqual(edited.saved);
  expect(isDirty(failed)).toBe(true);
  const retry = editorReducer(editName(failed, "Keep this too"), { type: "start", action: "save" });
  expect(retry.pending).toBeUndefined();
  expect(retry.feedback.authoringDisabled).toBe(true);
});

test("publication marks the submitted revision even if the operator has since edited", () => {
  const pending = editorReducer(saved(), { type: "start", action: "publish" });
  const complete = editorReducer(editName(pending, "Next draft"), { type: "complete", id: 1, result: { status: 200, revision: 3 } });
  expect(complete.saved?.publishedRevision).toBe(3);
  expect(complete.document.source.name).toBe("Next draft");
  expect(isDirty(complete)).toBe(true);
});

test("explicit reload ignores old responses and never reuses their request IDs", () => {
  const pending = editorReducer(saved(), { type: "start", action: "save" });
  const reloaded = editorReducer(pending, { type: "load", snapshot: { document, saved: { callSpecId: "appointments", revision: 5, publishedRevision: 2 } } });
  const next = editorReducer(reloaded, { type: "start", action: "save" });
  expect(next.pending?.id).toBe(2);
  expect(editorReducer(next, { type: "complete", id: 1, result: { status: 201, revision: 4 } })).toBe(next);
});

test("incomplete success metadata is retryable and never claims the draft was saved", () => {
  const pending = editorReducer(createEditorState({ document }), { type: "start", action: "save" });
  const result = editorReducer(pending, { type: "complete", id: 1, result: { status: 201, revision: 1 } });
  expect(result.saved).toBeUndefined();
  expect(isDirty(result)).toBe(true);
  expect(result.feedback.toast).toMatchObject({ tone: "error", action: "retry" });
});
