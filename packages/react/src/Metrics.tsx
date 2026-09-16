import type { Metric, MetricScope } from "@vxpipe/core";
import type { ConsoleSnapshot } from "./types.js";
import { MetricCellTooltip } from "./MetricCellTooltip.js";
import { MetricHeaderTooltip } from "./MetricHeaderTooltip.js";
import { participantDisplayName } from "./participantDisplayName.js";

const metricOrder = [
  "Call duration",
  "Turn duration",
  "Request duration",
  "Final transcript latency",
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
  metrics: Map<string, Metric>;
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

function metricRows(snapshot: ConsoleSnapshot) {
  const rows = new Map<string, MetricRow>();
  snapshot.metrics.forEach((metric) => {
    const key = scopeKey(metric.scope);
    const current = rows.get(key);
    if (current) {
      current.metrics.set(metric.label, metric);
      return;
    }
    rows.set(key, {
      key,
      scope: metric.scope,
      ...rowIdentity(metric.scope, snapshot),
      metrics: new Map([[metric.label, metric]]),
    });
  });
  return [...rows.values()].sort((left, right) => {
    const scopeDifference =
      scopeOrder.indexOf(left.scope.kind) - scopeOrder.indexOf(right.scope.kind);
    return scopeDifference || left.target.localeCompare(right.target);
  });
}

function metricColumns(metrics: readonly Metric[]) {
  const labels = new Set(metrics.map((metric) => metric.label));
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
}: {
  snapshot: ConsoleSnapshot;
  theme: "light" | "dark";
}) {
  const columns = metricColumns(snapshot.metrics);
  const rows = metricRows(snapshot);

  return (
    <section className="vx-metrics" aria-label="Call metrics">
      <div className="vx-metric-table-scroll">
        <table aria-label="Call metrics">
          <thead>
            <tr>
              <th scope="col">Target</th>
              {columns.map((column) => (
                <th scope="col" key={column.label} aria-label={column.label}>
                  <MetricHeaderTooltip
                    label={column.label}
                    shortLabel={column.shortLabel}
                    theme={theme}
                  />
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.key}>
                <th scope="row" aria-label={row.accessibleName}>
                  <strong>{row.target}</strong>
                  {row.participantName ? (
                    <span className="vx-metric-participant-badge">
                      {row.participantName}
                    </span>
                  ) : (
                    <small>{row.scopeLabel}</small>
                  )}
                </th>
                {columns.map((column) => (
                  <td key={column.label}>
                    <MetricCellTooltip
                      hideUnit={column.hideUnit}
                      label={column.label}
                      metric={row.metrics.get(column.label) ?? null}
                      target={row.accessibleName}
                      theme={theme}
                    />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
