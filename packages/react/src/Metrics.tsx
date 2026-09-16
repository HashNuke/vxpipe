import type { Metric } from "@vxpipe/core";

export function Metrics({ metrics }: { metrics: readonly Metric[] }) {
  return (
    <section className="vx-metrics" aria-label="Call metrics">
      <div className="vx-panel-intro">
        <h2>Metrics</h2>
        <p>
          Timing and usage reported for this call. Missing measurements stay
          unavailable.
        </p>
      </div>
      <div className="vx-metric-table">
        <div className="vx-metric-head">
          <span>Measurement</span>
          <span>Value</span>
          <span>Source</span>
        </div>
        {metrics.map((metric) => (
          <div className="vx-metric-row" key={metric.label}>
            <div>
              <strong>{metric.label}</strong>
              <p>{metric.description}</p>
            </div>
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
      <p className="vx-footnote">
        Each duration uses one clock. These values do not measure when a remote
        listener heard the audio.
      </p>
    </section>
  );
}
