import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useBlocker, useNavigate, useParams, useSearchParams } from "react-router";
import type { ModelCatalog } from "./admin/modelCatalog";
import { createEditorApi, EditorReadError, type EditorFetch } from "./admin/callSpecEditor/editor-api";
import { EditorPageState } from "./admin/callSpecEditor/editor-page-state";
import type { EditorSnapshot, SavedRevision } from "./admin/callSpecEditor/editor-state";
import { EditorTheme } from "./admin/callSpecEditor/EditorTheme";
import { CallSpecEditor } from "./admin/callSpecEditor/flow-editor";
import type { EditorLookups } from "./admin/callSpecEditor/inspectorTypes";
import { LeaveEditorDialog } from "./admin/callSpecEditor/leave-editor-dialog";
import { newCallSpec } from "./admin/callSpecEditor/seed";

const defaultFetch: EditorFetch = (input, init) => window.fetch(input, init);
type Page = { status: "loading" } | { status: "error"; resource: "spec" | "catalog"; expired: boolean } |
  { status: "ready"; snapshot: EditorSnapshot; catalog: ModelCatalog; lookups: EditorLookups; key: string };

export function CallSpecEditorRoute({ csrfToken, fetchImpl = defaultFetch }: { csrfToken: string; fetchImpl?: EditorFetch }) {
  const { tenantKey = "", callSpecId = "" } = useParams();
  const [query] = useSearchParams();
  const revisionQuery = query.get("revision");
  const navigate = useNavigate();
  const api = useMemo(() => createEditorApi(tenantKey, csrfToken, fetchImpl), [tenantKey, csrfToken, fetchImpl]);
  const base = `/admin/tenants/${encodeURIComponent(tenantKey)}`;
  const backHref = `${base}/call-specs`;
  const [page, setPage] = useState<Page>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const guarded = useRef(false);
  const proceeding = useRef(false);
  const allowed = useRef<string | undefined>(undefined);
  const created = useRef<string | undefined>(undefined);
  const blocker = useBlocker(({ nextLocation }) => {
    if (nextLocation.pathname === allowed.current) { allowed.current = undefined; return false; }
    return guarded.current;
  });
  useEffect(() => { if (blocker.state === "blocked") proceeding.current = false; }, [blocker.state]);
  const onGuardChange = useCallback((value: boolean) => { guarded.current = value; }, []);
  const approvedNavigate = useCallback((href: string) => { allowed.current = href; void navigate(href); }, [navigate]);
  const onSaved = useCallback((saved: SavedRevision) => {
    if (callSpecId !== "new") return;
    created.current = saved.callSpecId;
    const href = `${backHref}/${encodeURIComponent(saved.callSpecId)}`;
    allowed.current = href;
    void navigate(href, { replace: true });
  }, [backHref, callSpecId, navigate]);
  useEffect(() => {
    // Replacing /new after a save preserves the editor instance and edits made during that save.
    if (created.current === callSpecId && revisionQuery === null) { created.current = undefined; return; }
    const controller = new AbortController();
    let resource: "spec" | "catalog" = "catalog";
    const load = async () => {
      setPage({ status: "loading" });
      try {
        const catalog = await api.catalog(controller.signal);
        resource = "spec";
        const lookups = await api.lookups(controller.signal);
        const requested = revisionQuery === null ? undefined : Number(revisionQuery);
        if (requested !== undefined && (!/^[1-9]\d*$/.test(revisionQuery!) || !Number.isSafeInteger(requested) || requested > 2147483647)) throw new Error("Invalid revision");
        const snapshot = callSpecId === "new" ? { document: newCallSpec(catalog) } : await api.read(callSpecId, controller.signal, requested);
        if (!controller.signal.aborted) setPage({ status: "ready", snapshot, catalog, lookups, key: `${tenantKey}/${callSpecId}/${revisionQuery ?? "latest"}/${attempt}` });
      } catch (error) {
        if (!controller.signal.aborted) setPage({ status: "error", resource, expired: error instanceof EditorReadError && error.status === 401 });
      }
    };
    void load();
    return () => controller.abort();
  }, [api, tenantKey, callSpecId, revisionQuery, attempt]);
  const reload = useCallback((signal: AbortSignal) => api.read(created.current ?? callSpecId, signal), [api, callSpecId]);
  return <EditorTheme>
    {page.status === "ready" ? <>
      <CallSpecEditor noticeAction={revisionQuery !== null ? <Link className="underline" to={`${backHref}/${encodeURIComponent(callSpecId)}`}>Continue editing latest revision</Link> : undefined} key={page.key} snapshot={page.snapshot} catalog={page.catalog} lookups={page.lookups} execute={api.execute}
        backHref={backHref} servicesHref={`${base}/services`} onNavigate={approvedNavigate} onReload={reload} onGuardChange={onGuardChange} onSaved={onSaved} />
    </> : page.status === "error" && page.expired ? <main className="min-h-dvh bg-background p-6"><h1>Your session expired</h1><a className="underline" href="/auth/login">Sign in to open the editor</a></main> :
      <EditorPageState status={page.status} resource={page.status === "error" ? page.resource : undefined} backHref={backHref} onRetry={() => setAttempt((value) => value + 1)} />}
    <LeaveEditorDialog intent={blocker.state === "blocked" ? "leave" : null} onCancel={() => { if (blocker.state === "blocked" && !proceeding.current) blocker.reset(); }} onConfirm={() => { if (blocker.state === "blocked") { proceeding.current = true; blocker.proceed(); } }} />
  </EditorTheme>;
}
