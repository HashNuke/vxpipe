import { expect, test } from "vitest";
import { actionOutcome } from "./errorPresentation";
import { editorFixture } from "./editorFixtures";

test("publish success with recording_unavailable warns instead of silent success", () => {
  const result = actionOutcome(editorFixture.source, "publish", {
    status: 200,
    revision: 3,
    publication: { version: 6, revision: 3, unpublishedChanges: false, draftSavedAt: "2026-11-17T12:00:00Z", history: [] },
    validationWarnings: [
      {
        code: "recording_unavailable",
        path: ["media_policy", "record_audio"],
        reason: "Recording was requested but this installation has no recording storage.",
      },
    ],
  });
  expect(result.tone).toBe("success");
  expect(result.persistent).toBe(true);
  expect(result.message).toMatch(/recording requested/i);
  expect(result.message).toMatch(/Version 6 published/);
});

test("save success with recording_unavailable warns", () => {
  const result = actionOutcome(editorFixture.source, "save", {
    status: 201,
    revision: 4,
    validationWarnings: [{ code: "recording_unavailable", path: ["media_policy", "record_audio"] }],
  });
  expect(result.tone).toBe("success");
  expect(result.persistent).toBe(true);
  expect(result.message).toMatch(/recording requested/i);
});
