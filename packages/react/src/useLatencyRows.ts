import { useEffect, useState } from "react";
import { mergeLatencyReports, type LatencyLoader, type LatencyReport, type LatencyRun, type LatencyTurn } from "@vxpipe/core";

const maximumRunPages = 4;
const maximumTurnPages = 4;
const loadTimeoutMs = 10_000;
const liveRefreshMs = 5_000;

export interface LatencyRowsState {
  runs: readonly LatencyRun[];
  turns: ReadonlyMap<string, readonly LatencyTurn[]>;
  truncatedRuns: ReadonlySet<string>;
  loaded: boolean;
  loading: boolean;
  error?: "unavailable" | "denied";
  reload: () => void;
}

/** Keep the newest revision of each turn so a late or reordered refresh never regresses evidence. */
function mergeTurns(previous: readonly LatencyTurn[] | undefined, next: readonly LatencyTurn[]) {
  const retained = new Map(previous?.map(turn => [turn.turnId, turn]));
  return next.map(turn => {
    const current = retained.get(turn.turnId);
    return current && current.revision >= turn.revision ? current : turn;
  });
}

function status(failure: unknown) {
  return typeof failure === "object" && failure !== null && "status" in failure ? failure.status : undefined;
}

/** Bounded reads of every observation and its turns while the metrics table is shown. */
export function useLatencyRows(loader: LatencyLoader | undefined, live: boolean): LatencyRowsState {
  const [report, setReport] = useState<LatencyReport>();
  const [turns, setTurns] = useState<ReadonlyMap<string, readonly LatencyTurn[]>>(new Map());
  const [truncatedRuns, setTruncatedRuns] = useState<ReadonlySet<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<LatencyRowsState["error"]>();
  const [request, setRequest] = useState(0);

  useEffect(() => {
    if (!loader) return;
    const abort = new AbortController();
    let refreshTimer: ReturnType<typeof setTimeout> | undefined;
    const timeout = setTimeout(() => { abort.abort(); setLoading(false); setError("unavailable"); }, loadTimeoutMs);
    setLoading(true);
    void (async () => {
      try {
        let runs: LatencyRun[] = [];
        let cursor: string | null = null;
        for (let page = 0; page < maximumRunPages; page++) {
          const next = await loader.report(cursor, abort.signal);
          if (abort.signal.aborted) return;
          runs = [...runs, ...next.runs];
          cursor = next.nextCursor;
          if (cursor === null) break;
        }
        const loaded = new Map<string, LatencyTurn[]>();
        const truncated = new Set<string>();
        for (const run of runs) {
          let turnCursor: string | null = null;
          const runTurns: LatencyTurn[] = [];
          for (let page = 0; page < maximumTurnPages; page++) {
            const next = await loader.turns(run.id, turnCursor, abort.signal);
            if (abort.signal.aborted) return;
            if (next.runId !== run.id || next.turns.some(turn => turn.runId !== run.id)) throw new Error("Mismatched diagnostic run");
            runTurns.push(...next.turns);
            turnCursor = next.nextCursor;
            if (turnCursor === null) break;
          }
          if (turnCursor !== null) truncated.add(run.id);
          loaded.set(run.id, runTurns);
        }
        setReport(previous => mergeLatencyReports(previous, { runs, summary: [], nextCursor: null }));
        setTurns(previous => new Map(runs.map(run => [run.id, mergeTurns(previous.get(run.id), loaded.get(run.id) ?? [])])));
        setTruncatedRuns(truncated);
        setError(undefined);
        if (live) refreshTimer = setTimeout(() => setRequest(value => value + 1), liveRefreshMs);
      } catch (failure) {
        if (abort.signal.aborted) return;
        const code = status(failure);
        if (code === 401 || code === 403 || code === 404) {
          setReport(undefined); setTurns(new Map()); setTruncatedRuns(new Set()); setError("denied");
        } else setError("unavailable");
      } finally {
        clearTimeout(timeout);
        if (!abort.signal.aborted) setLoading(false);
      }
    })();
    return () => { abort.abort(); clearTimeout(timeout); clearTimeout(refreshTimer); };
  }, [loader, live, request]);

  return {
    runs: report?.runs ?? [], turns, truncatedRuns, loaded: report !== undefined, loading, error,
    reload: () => setRequest(value => value + 1),
  };
}
