import { useCallback, useEffect, useRef, useState } from "react";
import { createEditorState, editorReducer, isDirty, type EditorEvent, type EditorRequest, type EditorResult, type EditorSnapshot } from "./editor-state";
import type { SourceDocument } from "./types";
import type { ActionFeedback } from "./errorPresentation";

export type ExecuteEditorRequest = (request: EditorRequest, signal: AbortSignal) => Promise<EditorResult>;

// Transport is injected so the complete editor can run in Storybook before API wiring.
export function useEditor(snapshot: EditorSnapshot, execute: ExecuteEditorRequest, onSessionExpired?: () => void) {
  const [state, setState] = useState(() => createEditorState(snapshot));
  const current = useRef(state);
  const mounted = useRef(true);
  const active = useRef<AbortController | undefined>(undefined);
  const lastAction = useRef<EditorRequest["action"] | undefined>(undefined);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; active.current?.abort(); };
  }, []);

  const dispatch = useCallback((event: EditorEvent) => {
    // Keep event handlers synchronous: two clicks in one render cannot start two writes.
    const next = editorReducer(current.current, event);
    current.current = next;
    setState(next);
    return next;
  }, []);

  const start = useCallback((action: EditorRequest["action"]) => {
    if (!mounted.current || current.current.pending) return;
    const next = dispatch({ type: "start", action });
    const request = next.pending;
    if (!request) return;
    lastAction.current = action;
    const controller = new AbortController();
    active.current = controller;
    const run = async () => {
      let result: EditorResult;
      try { result = await execute(request, controller.signal); }
      catch { result = {}; }
      if (!mounted.current || controller.signal.aborted || current.current.pending?.id !== request.id) return;
      if (result.status === 400 && result.error?.code === "invalid_request") console.error("Call spec editor sent an invalid request.", { action: request.action });
      active.current = undefined;
      const expired = current.current.feedback.sessionExpired;
      const completed = dispatch({ type: "complete", id: request.id, result });
      if (!expired && completed.feedback.sessionExpired) onSessionExpired?.();
    };
    void run();
  }, [dispatch, execute, onSessionExpired]);

  const edit = useCallback((document: SourceDocument) => { dispatch({ type: "edit", document }); }, [dispatch]);
  const save = useCallback(() => start("save"), [start]);
  const publish = useCallback(() => start("publish"), [start]);
  const retry = useCallback(() => {
    if (lastAction.current && current.current.feedback.toast?.action === "retry") start(lastAction.current);
  }, [start]);
  const load = useCallback((next: EditorSnapshot) => {
    active.current?.abort();
    active.current = undefined;
    lastAction.current = undefined;
    dispatch({ type: "load", snapshot: next });
  }, [dispatch]);
  const dismissToast = useCallback(() => { dispatch({ type: "dismiss-toast" }); }, [dispatch]);
  const reportFeedback = useCallback((feedback: ActionFeedback) => { dispatch({ type: "feedback", feedback }); }, [dispatch]);
  return { state, dirty: isDirty(state), edit, save, publish, retry, load, dismissToast, reportFeedback };
}
