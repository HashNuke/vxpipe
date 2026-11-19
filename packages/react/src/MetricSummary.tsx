import type { Metric } from "@vxpipe/core";
import { MetricCellTooltip } from "./MetricCellTooltip.js";
import { metricUnit } from "./metricUnit.js";

export function MetricSummary({ metrics, label, target, hideUnit, theme }: {
  metrics: readonly Metric[];
  label: string;
  target: string;
  hideUnit: boolean;
  theme: "light" | "dark";
}) {
  const groups = new Map<string, Metric[]>();
  for (const metric of metrics) {
    const unit = metricUnit(metric.unit);
    const group = groups.get(unit);
    if (group) group.push(metric);
    else groups.set(unit, [metric]);
  }

  return <div className="vx-metric-summary" role="group" aria-label={`${label} summary for ${target}`}>
    {[...groups].map(([unit, observations]) => {
      const values = observations.flatMap(({ value }) => value !== null && Number.isFinite(value) ? [value] : [])
        .sort((left, right) => left - right);
      if (observations.length === 1 || values.length === 0) {
        return <MetricCellTooltip key={unit} label={label} target={target} hideUnit={hideUnit}
          metric={values.length === 0 ? null : observations[0]!} theme={theme} />;
      }
      const middle = Math.floor(values.length / 2);
      const median = values.length % 2 === 0 ? (values[middle - 1]! + values[middle]!) / 2 : values[middle]!;
      const total = values.reduce((sum, value) => sum + value, 0);
      const stats = [["Median", median], ["Avg", total / values.length], ["Total", total]] as const;
      return <div className="vx-metric-summary-group" key={unit}>
        <dl>{stats.map(([name, value]) => <div key={name}>
          <dt>{name}</dt>
          <dd>{Number.isFinite(value) ? value.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
            {!hideUnit && <> <small>{unit}</small></>}</dd>
        </div>)}</dl>
        {values.length !== observations.length &&
          <small className="vx-metric-summary-coverage">{values.length} of {observations.length} values</small>}
      </div>;
    })}
  </div>;
}
