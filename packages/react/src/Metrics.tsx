import type { CallSnapshot, Metric, MetricScope } from "@vxpipe/core";
import { MetricDescriptionTooltip } from "./MetricDescriptionTooltip.js";

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

function MetricRows({
  metrics,
  theme,
}: {
  metrics: readonly Metric[];
  theme: "light" | "dark";
}) {
  return (
    <div className="vx-metric-table">
      <div className="vx-metric-head">
        <span>Measurement</span>
        <span>Value</span>
        <span>Source</span>
      </div>
      {metrics.map((metric) => (
        <div className="vx-metric-row" key={metric.label}>
          <MetricDescriptionTooltip
            label={metric.label}
            description={metric.description}
            theme={theme}
          />
          <span className="vx-metric-value">
            {metric.value === null ? (
              "Unavailable"
            ) : (
              <>
                {metric.value.toLocaleString()} <small>{metric.unit}</small>
              </>
            )}
          </span>
          <span className="vx-metric-source">{metric.source}</span>
        </div>
      ))}
    </div>
  );
}

function subgroupLabel(metric: Metric, snapshot: CallSnapshot) {
  const scope = metric.scope;
  if (scope.kind === "room") return null;
  if (scope.kind === "room-capability") return scope.capability;
  const participant = snapshot.participants.find(
    (person) => person.id === scope.participantId,
  );
  const name = participant?.name ?? scope.participantId;
  return scope.kind === "participant-capability"
    ? `${name} · ${scope.capability}`
    : name;
}

function groupByLabel(metrics: readonly Metric[], snapshot: CallSnapshot) {
  const groups = new Map<string, Metric[]>();
  metrics.forEach((metric) => {
    const label = subgroupLabel(metric, snapshot) ?? "";
    groups.set(label, [...(groups.get(label) ?? []), metric]);
  });
  return [...groups.entries()];
}

export function Metrics({
  snapshot,
  theme,
}: {
  snapshot: CallSnapshot;
  theme: "light" | "dark";
}) {
  return (
    <section className="vx-metrics" aria-label="Call metrics">
      {scopeOrder.map((kind) => {
        const metrics = snapshot.metrics.filter(
          (metric) => metric.scope.kind === kind,
        );
        if (metrics.length === 0) return null;
        return (
          <section className="vx-metric-scope" key={kind}>
            <h2>{scopeLabels[kind]}</h2>
            {groupByLabel(metrics, snapshot).map(([label, scoped]) => (
              <div className="vx-metric-group" key={label || kind}>
                {label && <h3>{label}</h3>}
                <MetricRows metrics={scoped} theme={theme} />
              </div>
            ))}
          </section>
        );
      })}
    </section>
  );
}
