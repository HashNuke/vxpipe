import type { LatencyBargeIn } from "@vxpipe/core";

const ms = (value: number | null) => value === null ? "Unavailable" : value > 0 && value < 1000 ? "<1 ms" : `${Math.round(value / 1000).toLocaleString()} ms`;
const reason = (value: string) => value.replaceAll("_", " ");

export function BargeInSummary({ evidence }: { evidence: LatencyBargeIn | null | undefined }) {
  if (!evidence) return <>Unavailable<small>not recorded</small></>;
  if (evidence.entries.length === 0) return <>No interruption recorded</>;
  if (evidence.entries.length === 1) {
    const entry = evidence.entries[0]!;
    return <>{ms(entry.durationUs)}{entry.reasons.length > 0 && <small title={entry.reasons.map(reason).join(", ")}>{entry.reasons.map(reason).join(", ")}</small>}</>;
  }
  const values = evidence.entries.flatMap(entry => entry.durationUs === null ? [] : [entry.durationUs]).sort((a, b) => a - b);
  const median = values.length === 0 ? null : (values[Math.floor((values.length - 1) / 2)]! + values[Math.floor(values.length / 2)]!) / 2;
  return <>{ms(median)}{median !== null && " median"}<small>{values.length} valid of {evidence.entries.length} interruptions</small></>;
}

/** Onset belongs to this human turn; output identity may belong to an earlier or different human's response. */
export function BargeInEvidence({ evidence, name }: {
  evidence: LatencyBargeIn | null | undefined; name: (participantId: string) => string;
}) {
  if (!evidence) return <p>Barge-in evidence unavailable.</p>;
  return <section className="vx-barge-in-evidence" aria-label="Barge-in evidence">
    <h4>Barge-in stop delay</h4>
    <p>Estimated human speech onset to the server’s playback stop acknowledgement. Audio already buffered by the listener may continue briefly. Times use this observation’s clock origin.</p>
    {evidence.entries.length === 0 ? <p>No interruption recorded.</p> : <div className="vx-latency-table-scroll" tabIndex={0} role="region" aria-label="Barge-in measurements, scroll for more evidence">
      <table aria-label="Barge-in measurements">
        <thead><tr><th scope="col">Interrupted output</th><th scope="col">Human speech onset</th><th scope="col">Server playback stopped</th><th scope="col">Stop delay</th></tr></thead>
        <tbody>{evidence.entries.map((entry, index) => <tr key={`${entry.outputConnectionId}:${entry.outputId}:${index}`}>
          <th scope="row"><span>{name(entry.agentParticipantId)} responding to {name(entry.responseSourceParticipantId)}</span><small title={entry.outputId}>{entry.outputId}</small>
            <small title={entry.responseTurnId}>Response turn: {entry.responseTurnId}</small><small title={entry.outputConnectionId}>Output connection: {entry.outputConnectionId}</small></th>
          <td>{ms(entry.speechStartedUs)}<small>Confirmed {ms(entry.speechStartConfirmedUs)}</small><small>Uncertainty {ms(entry.uncertaintyUs)}</small></td>
          <td>{ms(entry.playbackStoppedUs)}<small>Interruption requested {ms(entry.interruptionRequestedUs)}</small><small>Playback started {ms(entry.playbackStartedUs)}</small></td>
          <td>{ms(entry.durationUs)}{entry.reasons.length > 0 && <small className="vx-barge-in-reasons">{entry.reasons.map(reason).join(", ")}</small>}</td>
        </tr>)}</tbody>
      </table>
    </div>}
    {evidence.omittedCount > 0 && <p>{evidence.omittedCount.toLocaleString()} additional interruptions omitted (entry limit).</p>}
  </section>;
}
