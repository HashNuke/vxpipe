import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import type { ModelCatalog } from "../modelCatalog";
import { ActionFailureContext } from "./action-failure-context";
import { editSource } from "./editSource";
import { FlowNameDialog } from "./editor-header";
import type { EditorSnapshot, SavedRevision } from "./editor-state";
import { EditorToast } from "./editor-toast";
import { locateIssue, type ActionFeedback } from "./errorPresentation";
import { FlowEditorLayout } from "./flow-editor-layout";
import { Inspector } from "./inspector";
import type { EditorLookups } from "./inspectorTypes";
import type { IssueRequest } from "./issue-context";
import { issueCounts, mergeIssues } from "./issues";
import { IssuesDrawer } from "./issues-drawer";
import { LeaveEditorDialog } from "./leave-editor-dialog";
import { addParticipant, setTransfer } from "./participants";
import { SourceView } from "./source-view";
import type { SourceDocument, SourceIssue } from "./types";
import { useEditor, type ExecuteEditorRequest } from "./use-editor";

export type CallSpecEditorProps = {
  snapshot: EditorSnapshot;
  noticeAction?: ReactNode;
  catalog: ModelCatalog;
  lookups: EditorLookups;
  execute: ExecuteEditorRequest;
  backHref: string;
  servicesHref: string;
  onNavigate: (href: string) => void;
  onReload: (signal: AbortSignal) => Promise<EditorSnapshot>;
  onSessionExpired?: () => void;
  onGuardChange?: (guarded: boolean) => void;
  onSaved?: (saved: SavedRevision) => void;
};
type Departure = { kind: "leave"; href: string } | { kind: "reload" };

export function CallSpecEditor({ snapshot, catalog, lookups, execute, backHref, servicesHref, onNavigate, onReload, onSessionExpired, onGuardChange, onSaved, noticeAction }: CallSpecEditorProps) {
  const editor = useEditor(snapshot, execute, onSessionExpired);
  const { state, reportFeedback } = editor;
  const [selectedNodeId, setSelectedNode] = useState<string | null>(null);
  const [selectedEdgeId, setSelectedEdge] = useState<string | null>(null);
  const [tab, setTab] = useState<string>();
  const [focusRequest, setFocusRequest] = useState<IssueRequest>();
  const [inspectorRequest, setInspectorRequest] = useState<number>();
  const requestId = useRef(0);
  const [issuesOpen, setIssuesOpen] = useState(false);
  const [sourceOpen, setSourceOpen] = useState(false);
  const [nameDraft, setNameDraft] = useState<string | null>(null);
  const [departure, setDeparture] = useState<Departure | null>(null);
  const [reloading, setReloading] = useState(false);
  const reloadController = useRef<AbortController | undefined>(undefined);
  const dirty = editor.dirty && !state.document.readOnly;
  const guarded = dirty || !!state.pending;
  const issues = mergeIssues(state.clientIssues, state.feedback.backend);
  const counts = issueCounts(state.document.source, issues);
  const document = reloading ? { ...state.document, readOnly: true } : state.document;

  useEffect(() => () => reloadController.current?.abort(), []);
  useEffect(() => { onGuardChange?.(guarded); return () => onGuardChange?.(false); }, [guarded, onGuardChange]);
  useEffect(() => { if (state.saved) onSaved?.(state.saved); }, [state.saved, onSaved]);
  useEffect(() => {
    if (!guarded) return;
    const preventLeave = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ""; };
    window.addEventListener("beforeunload", preventLeave);
    return () => window.removeEventListener("beforeunload", preventLeave);
  }, [guarded]);
  const reportFailure = useCallback((message: string) => reportFeedback({ tone: "error", persistent: true, message }), [reportFeedback]);
  function selectNode(id: string | null) { setSelectedNode(id); setSelectedEdge(null); setTab(undefined); setFocusRequest(undefined); }
  function change(operation: (document: SourceDocument) => SourceDocument, failure: string): boolean {
    try { editor.edit(operation(state.document)); return true; }
    catch { reportFailure(failure); return false; }
  }
  function add(kind: "agent" | "human") {
    let key = kind as string;
    for (let index = 2; Object.hasOwn(state.document.source.participants, key); index++) key = `${kind}_${index}`;
    if (change((document) => addParticipant(document, key, kind), "Couldn't add a participant. Try again.")) {
      selectNode(key); setInspectorRequest(++requestId.current);
    }
  }
  function show(issue: SourceIssue) {
    const location = locateIssue(state.document.source, issue.path);
    if (!location) { setIssuesOpen(true); return; }
    setSelectedNode(location.nodeId === "$settings" ? null : location.nodeId);
    setSelectedEdge(null); setTab(location.tab); setIssuesOpen(false);
    const id = ++requestId.current;
    setFocusRequest({ id, path: issue.path }); setInspectorRequest(id);
  }
  async function reload() {
    if (reloadController.current) return;
    const controller = new AbortController(); reloadController.current = controller; setReloading(true);
    try {
      const snapshot = await onReload(controller.signal);
      if (!controller.signal.aborted) { editor.load(snapshot); selectNode(null); }
    } catch {
      if (!controller.signal.aborted) reportFeedback({ tone: "error", persistent: true, message: "Couldn't reload. Your changes are still here.", action: "reload" });
    } finally {
      if (!controller.signal.aborted) { reloadController.current = undefined; setReloading(false); }
    }
  }
  function depart(next: Departure) {
    if (guarded) setDeparture(next);
    else if (next.kind === "leave") onNavigate(next.href);
    else void reload();
  }
  function toastAction(action: NonNullable<ActionFeedback["action"]>) {
    if (action !== "show" && (state.pending || reloading)) return;
    if (action === "retry") editor.retry();
    else if (action === "services") depart({ kind: "leave", href: servicesHref });
    else if (action === "reload") depart({ kind: "reload" });
    else {
      const issue = state.feedback.toast?.issue;
      if (issue) show({ code: issue.code, path: issue.path ?? [], reason: issue.reason ?? state.feedback.toast!.message });
      else setIssuesOpen(true);
    }
  }
  const inspector = <Inspector document={document} onChange={editor.edit} catalog={catalog} lookups={lookups} issues={issues} focusRequest={focusRequest}
    selectedNodeId={selectedNodeId} selectedEdgeId={selectedEdgeId} tab={tab} onTabChange={(tab) => { setTab(tab); setFocusRequest(undefined); }}
    onRenamed={selectNode} onRemoved={() => selectNode(null)} onDeleteEdge={(edge) => {
      if (!edge.locked && change((document) => setTransfer(document, edge.source, edge.target, false), "Couldn't delete this transfer. Try again.")) selectNode(null);
    }} />;
  return <ActionFailureContext value={reportFailure}>
    <FlowEditorLayout noticeAction={noticeAction} document={document} selectedNodeId={selectedNodeId} issues={counts.nodes} onSelectNode={selectNode}
      onSelectEdge={(id) => { setSelectedEdge(id); setSelectedNode(null); setFocusRequest(undefined); }} onAddNode={add}
      onConnect={(from, to) => { change((document) => setTransfer(document, from, to, true), "Couldn't connect these participants. Choose an agent and a transfer destination."); }}
      inspector={inspector} inspectorTitle={selectedEdgeId ? "Selected edge" : selectedNodeId === "$entry" ? "Entry settings" : selectedNodeId ? `Participant ${selectedNodeId}` : "Call settings"} inspectorRequest={inspectorRequest}
      backHref={backHref} onBack={() => depart({ kind: "leave", href: backHref })} revision={state.saved?.revision} publishedRevision={state.saved?.publishedRevision ?? undefined}
      dirty={dirty} issueCount={state.clientIssues.length} saving={state.pending?.action === "save"} publishing={state.pending?.action === "publish"} loading={reloading}
      saveDisabled={state.feedback.saveDisabled} authoringDisabled={state.feedback.authoringDisabled || state.feedback.sessionExpired}
      onEditFlowName={() => setNameDraft(state.document.source.name ?? "")} onSaveDraft={editor.save} onPublish={editor.publish} onShowIssues={() => setIssuesOpen(true)} onShowSource={() => setSourceOpen(true)} />
    <FlowNameDialog open={nameDraft !== null} value={nameDraft ?? ""} onValueChange={setNameDraft} onCancel={() => setNameDraft(null)} onSubmit={(event) => {
      event.preventDefault(); if (change((document) => editSource(document, (source) => { source.name = nameDraft ?? ""; }), "Couldn't change the call spec name.")) setNameDraft(null);
    }} />
    <IssuesDrawer open={issuesOpen} onOpenChange={setIssuesOpen} source={state.document.source} issues={issues} onShow={show} />
    <SourceView open={sourceOpen} onOpenChange={setSourceOpen} source={state.document.source} onFeedback={reportFeedback} />
    <EditorToast feedback={state.feedback.toast} onDismiss={editor.dismissToast} onAction={toastAction} busy={!!state.pending || reloading} />
    <LeaveEditorDialog intent={departure?.kind ?? null} onCancel={() => setDeparture(null)} onConfirm={() => {
      const next = departure; setDeparture(null); if (next?.kind === "leave") onNavigate(next.href); else if (next) void reload();
    }} />
  </ActionFailureContext>;
}
