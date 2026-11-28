import type { LatencyLoader, Metric, MetricScope } from "@vxpipe/core";
import { useId, useMemo, useState } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";
import type { ConsoleSnapshot } from "./types.js";
import { MetricCellTooltip } from "./MetricCellTooltip.js";
import { MetricHeaderTooltip } from "./MetricHeaderTooltip.js";
import { MetricSummary } from "./MetricSummary.js";
import { participantDisplayName } from "./participantDisplayName.js";
import { LatencyRowDetails, LatencySummaryCell, LatencyTurnCells } from "./LatencyCells.js";
import { bargeInLabel, endOfTurnLabel, latencyColumnDescriptions, latencyRows, type LatencyRow } from "./latencyRows.js";
import { DecisionsDetails } from "./DecisionsDetails.js";
import { groupDecisions, type DecisionsGroup } from "./decisionsMetrics.js";
import { useLatencyRows } from "./useLatencyRows.js";

/** Optional authorized diagnostics shown as VAD rows; failures never hide the call's metrics. */
export interface MetricsLatency {
  loader: LatencyLoader;
  live: boolean;
  onTranscript?: (messageId: string) => void;
}

const metricOrder = [
  "Call duration",
  "Evaluations",
  "API requests",
  "Turn duration",
  "Request duration",
  "Final transcript latency",
  endOfTurnLabel,
  bargeInLabel,
  "Median TTFT",
  "TTFT",
  "Median time to first audio",
  "Time to first audio",
  "A2FA",
  "Input tokens",
  "Output tokens",
  "Cached tokens",
  "TPOT",
  "TPS",
  "RTF",
  "Round-trip time",
  "Jitter",
  "Packet loss",
] as const;

const metricShortLabels: Readonly<Record<string, string>> = {
  "Call duration": "DUR",
  "Final transcript latency": "FTL",
  [endOfTurnLabel]: "EOT",
  [bargeInLabel]: "Barge-in",
  "Median TTFT": "Mdn TTFT",
  "Median time to first audio": "Mdn TTFA",
  "Round-trip time": "RTT",
  "Input tokens": "Input",
  "Output tokens": "Output",
  "Cached tokens": "Cached",
};

const scopeOrder: readonly MetricScope["kind"][] = [
  "room",
  "room-capability",
  "participant",
  "participant-capability",
];

const scopeLabels: Record<MetricScope["kind"], string> = {
  room: "Room",
  "room-capability": "Room capability",
  participant: "Participant",
  "participant-capability": "Participant capability",
};

interface MetricRow {
  key: string;
  scope: MetricScope;
  scopeLabel: string;
  target: string;
  accessibleName: string;
  participantName?: string;
  metrics: Map<string, Metric[]>;
  latency?: LatencyRow;
  decisions?: DecisionsGroup;
}

function scopeKey(scope: MetricScope) {
  if (scope.kind === "room") return "room";
  if (scope.kind === "room-capability")
    return `room-capability:${scope.capability}`;
  if (scope.kind === "participant")
    return `participant:${scope.participantId}`;
  return `participant-capability:${scope.participantId}:${scope.capability}`;
}

function rowIdentity(scope: MetricScope, snapshot: ConsoleSnapshot) {
  const scopeLabel = scopeLabels[scope.kind];
  if (scope.kind === "room")
    return { scopeLabel, target: "Call", accessibleName: "Room" };
  if (scope.kind === "room-capability")
    return {
      scopeLabel,
      target: scope.capability,
      accessibleName: `${scopeLabel}: ${scope.capability}`,
    };
  const participant = snapshot.participants.find(
    (person) => person.id === scope.participantId,
  );
  const participantName = participant
    ? participantDisplayName(participant)
    : scope.participantId;
  if (scope.kind === "participant-capability")
    return {
      scopeLabel,
      target: scope.capability,
      accessibleName: `${scope.capability}, ${participantName}`,
      participantName,
    };
  return {
    scopeLabel,
    target: participantName,
    accessibleName: `${scopeLabel}: ${participantName}`,
  };
}

function metricRows(snapshot: ConsoleSnapshot, metrics: readonly Metric[], groups: readonly DecisionsGroup[]) {
  const rows = new Map<string, MetricRow>();
  metrics.forEach((metric) => {
    const key = scopeKey(metric.scope);
    const current = rows.get(key);
    if (current) {
      const observations = current.metrics.get(metric.label) ?? [];
      observations.push(metric);
      current.metrics.set(metric.label, observations);
      return;
    }
    rows.set(key, {
      key,
      scope: metric.scope,
      ...rowIdentity(metric.scope, snapshot),
      metrics: new Map([[metric.label, [metric]]]),
    });
  });
  for (const group of groups) {
    const scope = { kind: "participant-capability", participantId: group.participantId, capability: "Decisions" } as const;
    const identity = rowIdentity(scope, snapshot);
    rows.set(group.key, { ...identity, scope, key: group.key, target: "Decisions", accessibleName: identity.accessibleName + ", " + group.model,
      decisions: group, metrics: group.metrics });
  }
  return [...rows.values()].sort((left, right) => {
    const scopeDifference =
      scopeOrder.indexOf(left.scope.kind) - scopeOrder.indexOf(right.scope.kind);
    return scopeDifference || left.target.localeCompare(right.target);
  });
}

function lastIndex<T>(items: readonly T[], predicate: (item: T) => boolean) {
  for (let index = items.length - 1; index >= 0; index--) if (predicate(items[index]!)) return index;
  return -1;
}

/** Each VAD row follows its participant's STT row, or that participant's last row. */
function withLatencyRows(rows: MetricRow[], latency: readonly LatencyRow[], snapshot: ConsoleSnapshot) {
  const result = [...rows];
  for (const row of latency) {
    const scope: MetricScope = { kind: "participant-capability", participantId: row.participantId, capability: "VAD" };
    const entry: MetricRow = { key: row.key, scope, ...rowIdentity(scope, snapshot), metrics: new Map(), latency: row };
    const owned = (candidate: MetricRow) => "participantId" in candidate.scope && candidate.scope.participantId === row.participantId;
    const stt = lastIndex(result, candidate => owned(candidate) && "capability" in candidate.scope &&
      ["STT", "VAD"].includes(candidate.scope.capability));
    const anchor = stt >= 0 ? stt : lastIndex(result, owned);
    result.splice(anchor >= 0 ? anchor + 1 : result.length, 0, entry);
  }
  return result;
}

function metricColumns(metrics: readonly Metric[], latency: boolean) {
  const labels = new Set(metrics.map((metric) => metric.label));
  if (latency) { labels.add(endOfTurnLabel); labels.add(bargeInLabel); }
  const preferred = metricOrder.filter((label) => labels.delete(label));
  const ordered = [
    ...preferred,
    ...[...labels].sort((left, right) => left.localeCompare(right)),
  ];
  return ordered.map((label) => ({
    label,
    shortLabel: metricShortLabels[label] ?? label,
    hideUnit: label.endsWith("tokens"),
  }));
}

export function Metrics({
  snapshot,
  theme,
  latency,
  onShowGuardrail,
}: {
  snapshot: ConsoleSnapshot;
  theme: "light" | "dark";
  latency?: MetricsLatency;
  onShowGuardrail?: (evaluationId: string) => void;
}) {
  const diagnostics = useLatencyRows(latency?.loader, latency?.live ?? false);
  const latencyData = useMemo(() => latencyRows(diagnostics.runs, diagnostics.turns, diagnostics.truncatedRuns),
    [diagnostics.runs, diagnostics.turns, diagnostics.truncatedRuns]);
  const decisions = useMemo(() => groupDecisions(snapshot.guardrails ?? [], snapshot.metrics), [snapshot.guardrails, snapshot.metrics]);
  const columns = metricColumns([...decisions.otherMetrics, ...decisions.groups.flatMap(group => [...group.metrics.values()].flat())],
    latencyData.length > 0);
  const rows = withLatencyRows(metricRows(snapshot, decisions.otherMetrics, decisions.groups), latencyData, snapshot);
  const [selected, setSelected] = useState<{ callId: string; key: string } | null>(null);
  const selectedGroup = selected?.callId === snapshot.callId ? decisions.groups.find(group => group.key === selected.key) : undefined;
  const detailId = useId();
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const tableId = useId();
  const participantName = (id: string) => {
    const participant = snapshot.participants.find((person) => person.id === id);
    return participant ? participantDisplayName(participant) : id;
  };
  const expandable = rows.filter((row) => row.latency ? row.latency.turns.length > 0 :
    !("capability" in row.scope && ["STT", "Agent STT"].includes(row.scope.capability)) &&
    [...row.metrics.values()].some((values) => values.length > 1));
  const latencyStatus = latency && <LatencyStatus diagnostics={diagnostics} />;
  const anyExpanded = expandable.some((row) => expanded.has(row.key));
  const allExpanded = expandable.every((row) => expanded.has(row.key));

  if (decisions.groups.length === 0 && latencyData.length === 0 && (snapshot.metricsAvailability === "unavailable" || snapshot.metrics.length === 0)) {
    return (
      <section className="vx-metrics vx-metrics-empty" aria-label="Call metrics">
        <p>{snapshot.metricsAvailability === "unavailable" ? "Metrics unavailable." : "No metrics recorded."}</p>
        {latencyStatus}
      </section>
    );
  }

  return (
    <section className={decisions.groups.length ? "vx-metrics vx-metrics-with-decisions" : "vx-metrics"} aria-label="Call metrics">
      {latencyStatus}
      {expandable.length > 0 && <div className="vx-metric-toolbar">
        <span>{anyExpanded ? (allExpanded ? "Individual measurements" : "Summary + individual measurements") :
          latencyData.length > 0 ? "Median · Avg · Total (VAD: Median · p95)" : "Median · Avg · Total"}</span>
        <div className="vx-metric-toolbar-actions">
        {latency && !latency.live && diagnostics.loaded && !diagnostics.error && diagnostics.runs.length > 0 &&
          <button type="button" className="vx-metric-expand-toggle" onClick={diagnostics.reload}
            disabled={diagnostics.loading}>Refresh diagnostics</button>}
        <button type="button" className="vx-metric-expand-toggle" aria-controls={tableId}
          aria-expanded={anyExpanded}
          onClick={() => setExpanded(anyExpanded ? new Set() : new Set(expandable.map((row) => row.key)))}>
          {anyExpanded ? "Collapse all" : "Expand all"}
        </button>
        </div>
      </div>}
      <div className="vx-metric-table-scroll">
        <table aria-label="Call metrics" id={tableId}>
          <thead>
            <tr>
              <th scope="col">Target</th>
              {columns.map((column) => (
                <th scope="col" key={column.label} aria-label={column.label}>
                  <MetricHeaderTooltip
                    label={column.label}
                    shortLabel={column.shortLabel}
                    description={latencyColumnDescriptions[column.label]}
                    theme={theme}
                  />
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, rowIndex) => (
              <tr key={row.key} id={`${tableId}-${rowIndex}`}>
                <th scope="row" aria-label={row.accessibleName}>
                  <div className="vx-metric-target">
                  <div>
                  {row.latency ? <span className="vx-metric-target-label"><strong>{row.target}</strong>
                    <LatencyRowDetails row={row.latency} target={row.accessibleName}
                      participantName={row.participantName ?? row.latency.participantId} theme={theme} /></span> :
                    <strong>{row.target}</strong>}
                  {row.decisions && <small>{row.decisions.model}</small>}
                  {row.participantName ? (
                    <span className="vx-metric-participant-badge">
                      {row.participantName}
                    </span>
                  ) : (
                    <small>{row.scopeLabel}</small>
                  )}
                  {row.decisions && <button type="button" className="vx-decisions-link"
                    aria-label={`Inspect checks for ${row.accessibleName}`} aria-controls={detailId}
                    aria-expanded={selectedGroup?.key === row.key}
                    onClick={() => setSelected(selectedGroup?.key === row.key ? null : { callId: snapshot.callId, key: row.key })}>
                    Inspect checks</button>}
                  </div>
                  {expandable.includes(row) && <button type="button" className="vx-metric-row-toggle"
                    aria-label={`${expanded.has(row.key) ? "Collapse" : "Expand"} metrics for ${row.accessibleName}`}
                    aria-expanded={expanded.has(row.key)} aria-controls={`${tableId}-${rowIndex}`}
                    onClick={() => setExpanded((previous) => {
                      const next = new Set(previous);
                      if (next.has(row.key)) next.delete(row.key); else next.add(row.key);
                      return next;
                    })}>
                    {expanded.has(row.key) ? <ChevronDown size={16} aria-hidden="true" /> : <ChevronRight size={16} aria-hidden="true" />}
                  </button>}
                  </div>
                </th>
                {columns.map((column) => (
                  <td key={column.label}>
                    {row.latency && column.label in latencyColumnDescriptions ? (expanded.has(row.key) ?
                      <LatencyTurnCells row={row.latency} label={column.label} target={row.accessibleName}
                        participantName={row.participantName ?? row.latency.participantId} theme={theme}
                        name={participantName} messages={snapshot.messages} onTranscript={latency?.onTranscript} /> :
                      <LatencySummaryCell row={row.latency} label={column.label} target={row.accessibleName} />) :
                    !expanded.has(row.key) && (row.metrics.get(column.label)?.length ?? 0) > 1 ?
                      <MetricSummary metrics={row.metrics.get(column.label)!} label={column.label}
                        target={row.accessibleName} hideUnit={column.hideUnit} theme={theme} /> :
                    <div className="vx-metric-observations">
                      {(row.metrics.get(column.label) ?? [null]).map(
                        (metric, index) => (
                          <MetricCellTooltip
                            hideUnit={column.hideUnit}
                            key={`${metric?.source ?? "unavailable"}:${index}`}
                            label={column.label}
                            metric={metric}
                            target={row.accessibleName}
                            theme={theme}
                          />
                        ),
                      )}
                    </div>}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {decisions.groups.length > 0 && <DecisionsDetails checks={decisions.checks} unlinkedRequests={decisions.unlinkedRequests} rewrites={decisions.rewrites} group={selectedGroup} id={detailId}
        participantName={selectedGroup && participantName(selectedGroup.participantId)} onShowGuardrail={onShowGuardrail} />}
    </section>
  );
}

function LatencyStatus({ diagnostics }: { diagnostics: ReturnType<typeof useLatencyRows> }) {
  const retry = <button type="button" className="vx-metric-expand-toggle" onClick={diagnostics.reload}
    disabled={diagnostics.loading}>Retry diagnostics</button>;
  if (diagnostics.error === "denied") return <div className="vx-metric-latency-status" role="alert">
    <span>You do not have access to latency diagnostics, or the call is no longer available.</span></div>;
  if (diagnostics.error) return <div className="vx-metric-latency-status" role="alert">
    <span>Latency diagnostics could not be loaded.{diagnostics.loaded && " Showing previously loaded evidence."}</span>{retry}</div>;
  if (!diagnostics.loaded) return diagnostics.loading
    ? <div className="vx-metric-latency-status" role="status"><span>Loading latency diagnostics…</span></div> : null;
  if (diagnostics.runs.length === 0) return <div className="vx-metric-latency-status">
    <span>Latency diagnostics were not collected for this call. Collection may have been off, unsupported, or denied by the source policy.</span></div>;
  return null;
}
