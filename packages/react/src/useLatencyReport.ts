import { useEffect, useRef, useState } from "react";
import { mergeLatencyTurns, type LatencyLoader, type LatencyReport, type LatencyTurnPage } from "@vxpipe/core";

/** One bounded report page and one turn page. Refresh runs only while visible. */
export function useLatencyReport(loader: LatencyLoader, open: boolean, live: boolean) {
  const [report, setReport] = useState<LatencyReport>();
  const [turns, setTurns] = useState<LatencyTurnPage>();
  const [runId, setRunId] = useState<string | null>(null);
  const effectiveRun = useRef<string | null>(null);
  const [runCursor, setRunCursor] = useState<string | null>(null);
  const [turnCursor, setTurnCursor] = useState<string | null>(null);
  const [request, setRequest] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (!open) return;
    const abort = new AbortController();
    let refreshTimer: ReturnType<typeof setTimeout> | undefined;
    const timeout = setTimeout(() => {
      abort.abort();
      setLoading(false);
      setError("Latency diagnostics could not be loaded. Try again.");
    }, 10_000);
    setLoading(true); setError(undefined);
    void (async () => {
      try {
        const next = await loader.report(runCursor, abort.signal);
        if (abort.signal.aborted) return;
        const selected = next.runs.find(run => run.id === runId) ?? next.runs.find(run => run.id === effectiveRun.current) ?? next.runs[0];
        setReport(next);
        if (selected && selected.id !== effectiveRun.current) {
          effectiveRun.current = selected.id;
          if (turnCursor !== null) {
            setTurnCursor(null);
            setTurns(undefined);
            return;
          }
        }
        if (selected) {
          const page = await loader.turns(selected.id, turnCursor, abort.signal);
          if (abort.signal.aborted) return;
          if (page.runId !== selected.id || page.turns.some(turn => turn.runId !== selected.id)) {
            throw new Error("Mismatched diagnostic run");
          }
          setTurns(previous => mergeLatencyTurns(previous, page));
        } else { setTurns(undefined); }
        if (live) refreshTimer = setTimeout(() => setRequest(value => value + 1), 5_000);
      } catch (failure) {
        if (!abort.signal.aborted) {
          const status = typeof failure === "object" && failure !== null && "status" in failure ? failure.status : undefined;
          if (status === 401 || status === 403 || status === 404) { setReport(undefined); setTurns(undefined); }
          setError(status === 401 || status === 403 || status === 404
            ? "You do not have access to these diagnostics, or the call is no longer available."
            : "Latency diagnostics could not be loaded. Try again.");
        }
      } finally {
        clearTimeout(timeout);
        if (!abort.signal.aborted) setLoading(false);
      }
    })();
    return () => { abort.abort(); clearTimeout(timeout); clearTimeout(refreshTimer); };
  }, [loader, open, live, runId, runCursor, turnCursor, request]);

  return {
    report, turns, loading, error,
    runId: report?.runs.find(run => run.id === runId)?.id ?? report?.runs.find(run => run.id === effectiveRun.current)?.id ?? report?.runs[0]?.id,
    runCursor, turnCursor,
    reload: () => setRequest(value => value + 1),
    selectRun: (value: string) => { setRunId(value); setTurnCursor(null); setTurns(undefined); },
    pageRuns: (cursor: string | null) => { effectiveRun.current = null; setRunCursor(cursor); setRunId(null); setTurnCursor(null); setTurns(undefined); },
    pageTurns: (cursor: string | null) => { setTurnCursor(cursor); },
  };
}
