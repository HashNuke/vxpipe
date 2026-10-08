import { expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { applyActionResult, emptyActionFeedback, feedbackAfterEdit } from "./action-feedback";
const source = editorFixture.source;
const result = { status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "Prompt is required" } };

test("a validation failure persists through retries and publish success, then clears on save success", () => {
  const failed = applyActionResult(emptyActionFeedback(), source, "save", result);
  expect(failed.backend).toEqual(result.error);
  const retry = applyActionResult(failed, source, "save", { status: 503 });
  expect(retry.backend).toEqual(result.error);
  expect(retry.toast?.action).toBe("retry");
  const published = applyActionResult(retry, source, "publish", { status: 200, revision: 3 });
  expect(published.backend).toEqual(result.error);
  expect(published.toast?.message).toBe("Published revision 3");
  expect(applyActionResult(published, source, "save", { status: 201, revision: 4 }).backend).toBeUndefined();
});
test("edits retain the action outcome but clear only the edited backend field", () => {
  const failed = applyActionResult(emptyActionFeedback(), source, "save", result);
  const next = structuredClone(source); next.name = "Changed name";
  expect(feedbackAfterEdit(failed, source, next).backend).toEqual(result.error);
  next.participants.intake = { type: "agent", prompt: "Changed prompt" };
  const updated = feedbackAfterEdit(failed, source, next);
  expect(updated.backend).toBeUndefined(); expect(updated.toast).toEqual(failed.toast);
});
test("a late backend error is not attached to a field already changed since submission", () => {
  const current = structuredClone(source); current.participants.intake = { type: "agent", prompt: "Already fixed" };
  const state = applyActionResult(emptyActionFeedback(), current, "save", result, source);
  expect(state.backend).toBeUndefined(); expect(state.toast?.tone).toBe("error");
});
test("client-blocked actions replace the toast without introducing a backend issue", () => {
  const state = applyActionResult(emptyActionFeedback(), source, "save", { clientIssues: [result.error] });
  expect(state.toast?.message).toBe("Fix 1 issue before saving"); expect(state.backend).toBeUndefined();
});
test("missing specs, forbidden authoring and expired sessions retain explicit authoring gates", () => {
  const missing = applyActionResult(emptyActionFeedback(), source, "save", { status: 404, error: { code: "call_spec_not_found" } });
  expect(missing.saveDisabled).toBe(true); expect(missing.authoringDisabled).toBe(false);
  const forbidden = applyActionResult(missing, source, "publish", { status: 403, error: { code: "authoring_forbidden" } });
  expect(forbidden.authoringDisabled).toBe(true);
  const expired = applyActionResult(forbidden, source, "save", { status: 401 });
  expect(expired.sessionExpired).toBe(true); expect(expired.saveDisabled).toBe(true);
});
