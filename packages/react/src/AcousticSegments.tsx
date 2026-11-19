import type { LatencyAcousticSegments } from "@vxpipe/core";

const ms = (value: number | null) => value === null ? "Unavailable" : `${Math.round(value / 1000).toLocaleString()} ms`;
const reason = (value: string) => value.replaceAll("_", " ");

/** Local acoustic evidence stays inside its enclosing participant/source observation. */
export function AcousticSegments({ evidence, label = "Speech segments" }: {
  evidence: LatencyAcousticSegments | null | undefined; label?: string;
}) {
  if (!evidence) return <p>Speech segment evidence unavailable.</p>;
  return <section className="vx-acoustic-segments" aria-label={label}>
    <h4>{label}</h4>
    {evidence.entries.length === 0 ? <p>No speech segments recorded.</p> : <>
      <p>Local VAD estimates. A pause can separate segments within one conversational turn. Times use this observation’s clock origin.</p>
      <div className="vx-latency-table-scroll" tabIndex={0} role="region" aria-label={`${label}, scroll for more evidence`}>
        <table aria-label={label}>
          <thead><tr><th scope="col">Segment</th><th scope="col">Estimated start</th><th scope="col">Estimated end</th><th scope="col">Evidence</th></tr></thead>
          <tbody>{evidence.entries.map((segment, index) => <tr key={`${segment.epoch}:${segment.startSample}:${segment.endSample}`}>
            <th scope="row">{index + 1}<small>Epoch {segment.epoch}</small></th>
            <td>{ms(segment.startUs)}<small>Confirmed {ms(segment.startConfirmedUs)}</small><small>Sample {segment.startSample ?? "Unavailable"}</small></td>
            <td>{ms(segment.endUs)}<small>Confirmed {ms(segment.endConfirmedUs)}</small><small>Sample {segment.endSample ?? "Unavailable"}</small></td>
            <td>{segment.reasons.length > 0 && <span>{segment.reasons.map(reason).join(", ")}</span>}<small>Uncertainty {ms(segment.uncertaintyUs)}</small></td>
          </tr>)}</tbody>
        </table>
      </div>
    </>}
    {evidence.omittedCount > 0 && <p>{evidence.omittedCount.toLocaleString()} additional segments omitted ({evidence.reasons.map(reason).join(", ")}).</p>}
    {evidence.omittedCount === 0 && evidence.reasons.length > 0 && <p>Coverage: {evidence.reasons.map(reason).join(", ")}.</p>}
  </section>;
}
