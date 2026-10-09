import { stringifySourceJson } from "./source-json";
import { applyActionResult, emptyActionFeedback, feedbackAfterEdit, type EditorActionFeedback } from "./action-feedback";
import type { ActionFeedback, ActionResult } from "./errorPresentation";
import type { CallSpecSource, SourceDocument, SourceIssue } from "./types";
import { validateSource } from "./validation";

export type SavedRevision = { callSpecId: string; revision: number; publishedRevision: number | null };
export type EditorSnapshot = { document: SourceDocument; saved?: SavedRevision };
export type EditorRequest = {
  id: number;
  action: "save" | "publish";
  source: CallSpecSource;
  callSpecId?: string;
  revision?: number;
};
export type EditorState = EditorSnapshot & {
  savedSource?: CallSpecSource;
  clientIssues: SourceIssue[];
  feedback: EditorActionFeedback;
  pending?: EditorRequest;
  nextRequestId: number;
};
export type EditorResult = ActionResult & { callSpecId?: string };
export type EditorEvent =
  | { type: "edit"; document: SourceDocument }
  | { type: "start"; action: "save" | "publish" }
  | { type: "complete"; id: number; result: EditorResult }
  | { type: "load"; snapshot: EditorSnapshot }
  | { type: "feedback"; feedback: ActionFeedback }
  | { type: "dismiss-toast" };

export function createEditorState(snapshot: EditorSnapshot): EditorState {
  const copy = structuredClone(snapshot);
  return { ...copy, savedSource: copy.saved ? structuredClone(copy.document.source) : undefined,
    clientIssues: validateSource(copy.document.source), feedback: emptyActionFeedback(), nextRequestId: 1 };
}

export function isDirty(state: EditorState): boolean {
  return !state.savedSource || stringifySourceJson(state.document.source) !== stringifySourceJson(state.savedSource);
}

export function editorReducer(state: EditorState, event: EditorEvent): EditorState {
  switch (event.type) {
    case "load":
      // A confirmed reload invalidates pending work without recycling its ID.
      return { ...createEditorState(event.snapshot), nextRequestId: state.nextRequestId };
    case "edit":
      if (state.document.readOnly) return state;
      return { ...state, document: event.document, clientIssues: validateSource(event.document.source),
        feedback: feedbackAfterEdit(state.feedback, state.document.source, event.document.source) };
    case "dismiss-toast":
      return { ...state, feedback: { ...state.feedback, toast: null } };
    case "feedback":
      return { ...state, feedback: { ...state.feedback, toast: event.feedback } };
    case "start":
      return startAction(state, event.action);
    case "complete":
      return completeAction(state, event.id, event.result);
  }
}

function startAction(state: EditorState, action: EditorRequest["action"]): EditorState {
  if (state.pending || state.document.readOnly || state.feedback.authoringDisabled || state.feedback.sessionExpired ||
    (action === "save" && state.feedback.saveDisabled)) return state;
  if (state.clientIssues.length) return { ...state,
    feedback: applyActionResult(state.feedback, state.document.source, action, { clientIssues: state.clientIssues }) };
  if (action === "publish" && (!state.saved || isDirty(state))) return state;
  return { ...state, nextRequestId: state.nextRequestId + 1,
    pending: { id: state.nextRequestId, action, source: structuredClone(state.document.source),
      callSpecId: state.saved?.callSpecId, revision: state.saved?.revision } };
}

function completeAction(state: EditorState, id: number, received: EditorResult): EditorState {
  const request = state.pending;
  if (!request || request.id !== id) return state;
  const callSpecId = received.callSpecId ?? request.callSpecId;
  const success = received.status !== undefined && received.status >= 200 && received.status < 300;
  const validRevision = Number.isSafeInteger(received.revision) && received.revision! > 0;
  const validIdentity = !!callSpecId && (!request.callSpecId || callSpecId === request.callSpecId);
  const validPublication = request.action !== "publish" || received.revision === request.revision;
  // Malformed success must not clear an unsaved draft or claim a revision was saved.
  const result = success && !(validRevision && validIdentity && validPublication) ? {} : received;
  const feedback = applyActionResult(state.feedback, state.document.source, request.action, result, request.source);
  const next = { ...state, pending: undefined, feedback };
  if (feedback.toast?.tone !== "success") return next;
  if (request.action === "save") return { ...next, savedSource: request.source,
    saved: { callSpecId: callSpecId!, revision: received.revision!, publishedRevision: state.saved?.publishedRevision ?? null } };
  return { ...next, saved: { ...state.saved!, publishedRevision: request.revision! } };
}
