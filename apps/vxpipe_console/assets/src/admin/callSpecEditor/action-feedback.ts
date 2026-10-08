import { actionOutcome, type ActionFeedback, type ActionResult } from "./errorPresentation";
import { backendIssue, retainBackendIssue } from "./issues";
import type { CallSpecSource, SourceIssue } from "./types";
export type EditorActionFeedback = {
  toast: ActionFeedback | null;
  backend?: SourceIssue;
  saveDisabled: boolean;
  authoringDisabled: boolean;
  sessionExpired: boolean;
};
export function emptyActionFeedback(): EditorActionFeedback {
  return { toast: null, saveDisabled: false, authoringDisabled: false, sessionExpired: false };
}
export function applyActionResult(previous: EditorActionFeedback, current: CallSpecSource, action: "save" | "publish", result: ActionResult, submitted = current): EditorActionFeedback {
  const toast = actionOutcome(current, action, result);
  const issue = backendIssue(current, result);
  const backend = action === "save" && toast.tone === "success" ? undefined
    : issue ? retainBackendIssue(issue, submitted, current) : previous.backend;
  return { toast, backend,
    saveDisabled: previous.saveDisabled || !!toast.disableSave,
    authoringDisabled: previous.authoringDisabled || !!toast.disableAuthoring,
    sessionExpired: previous.sessionExpired || !!toast.sessionExpired,
  };
}
export function feedbackAfterEdit(previous: EditorActionFeedback, before: CallSpecSource, next: CallSpecSource): EditorActionFeedback {
  return { ...previous, backend: retainBackendIssue(previous.backend, before, next) };
}
