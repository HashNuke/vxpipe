import { useId, useState } from "react";
import type { LatencyLoader, LatencyMetric, LatencyTurn, Message, Participant } from "@vxpipe/core";
import { ChevronDown, ChevronRight } from "lucide-react";
import { useLatencyReport } from "./useLatencyReport.js";

const stages: ReadonlyArray<[LatencyMetric, string]> = [
  ["speech_end_to_provider_end", "STT latency"], ["provider_to_room", "Dispatch"],
  ["room_to_first_text", "Response text"], ["text_to_first_audio", "Audio start"],
];
const landmarks = {
  acoustic_end: "Estimated speech end", observer_confirmed: "Observer confirmation",
  provider_text_commit: "Transcript committed", provider_end_received: "STT turn ended",
  adapter_end_emitted: "Adapter end", room_turn_completed: "Room accepted turn",
  first_response_text: "Response text ready", first_audio_started: "Audio started", manual_commit_sent: "Manual commit sent",
};
function ms(value: number | null | undefined) {
  return value == null ? "Unavailable" : `${Math.round(value / 1000).toLocaleString()} ms`;
}
function reason(value: string | null | undefined) { return value?.replaceAll("_", " ") ?? "missing evidence"; }

function TurnRow({ turn, index, onTranscript }: { turn: LatencyTurn; index: number; onTranscript?: () => void }) {
  const [expanded, setExpanded] = useState(false);
  const id = useId();
  return <>
    <tr>
      <th scope="row"><button type="button" className="vx-latency-row-toggle" aria-expanded={expanded} aria-controls={id}
        onClick={() => setExpanded(value => !value)}>
        <span>Turn {index + 1}</span>{expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
      </button><small title={turn.turnId}>{turn.turnId}</small>{onTranscript && <button type="button" aria-label={`View transcript for turn ${index + 1}`} onClick={onTranscript}>View transcript</button>}</th>
      {stages.map(([key]) => <td key={key} title={turn.durationsUs[key] == null ? reason(turn.metricReasons[key]) : undefined}>
        {ms(turn.durationsUs[key])}
      </td>)}
      <td>{turn.quality === "available" ? "Available" : turn.quality === "incomplete" ? "Incomplete" : "Unavailable"}
        {turn.acousticReason && <small>{reason(turn.acousticReason)}</small>}</td>
    </tr>
    {expanded && <tr id={id}><td colSpan={6} className="vx-latency-evidence">
      <p>Landmarks are offsets from this run’s clock origin. Audio started means acknowledged server egress, not remote hearing.</p>
      <dl>{Object.entries(landmarks).map(([key, label]) => <div key={key}><dt>{label}</dt><dd>{ms(turn.landmarksUs[key as keyof typeof landmarks])}</dd></div>)}</dl>
      <dl>{stages.filter(([key]) => turn.durationsUs[key] == null).map(([key, label]) => <div key={key}><dt>{label} unavailable</dt><dd>{reason(turn.metricReasons[key])}</dd></div>)}</dl>
      <p>Clock: {turn.clockId} · Source: {turn.sourceEpoch} · Revision {turn.revision} · Timing uncertainty: {ms(turn.uncertaintyUs)}</p>
      <p>Speech end to audio start: {ms(turn.durationsUs.speech_end_to_first_audio)}. Missing stages are not zero latency.</p>
    </td></tr>}
  </>;
}

export function LatencyDiagnostics({ loader, live, participants, messages = [], onTranscript }: {
  messages?: readonly Message[]; onTranscript?: (messageId: string) => void;
  loader: LatencyLoader; live: boolean; participants: readonly Pick<Participant, "id" | "name">[];
}) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const data = useLatencyReport(loader, open, live);
  const run = data.report?.runs.find(value => value.id === data.runId);
  const name = (participantId: string) => participants.find(person => person.id === participantId)?.name ?? participantId;
  return <section className="vx-latency" aria-label="Latency diagnostics">
    <button type="button" className="vx-latency-toggle" aria-expanded={open} aria-controls={id} onClick={() => setOpen(value => !value)}>
      <span>Latency diagnostics</span>{open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
    </button>
    {open && <div id={id} className="vx-latency-body">
      <p className="vx-latency-description">Estimated speech end to STT turn end, then dispatch, response text and audio. Includes silence detection and network time; this is not pure provider compute.</p>
      {data.loading && <p role="status">{data.report ? "Refreshing diagnostics…" : "Loading diagnostics…"}</p>}
      {data.error && <div role="alert"><p>{data.error}</p>{data.report && <p>Showing previously loaded evidence.</p>}<button type="button" onClick={data.reload}>Retry diagnostics</button></div>}
      {!data.loading && !data.error && data.report?.runs.length === 0 && <p>{data.runCursor ? "No observations on this page." : "Not collected for this call. Collection may have been off, unsupported, or denied by the source policy."}</p>}
      {data.report && <div className="vx-latency-toolbar">
        {data.runCursor && <button type="button" onClick={() => data.pageRuns(null)} disabled={data.loading}>First observations</button>}
        {data.report.nextCursor && <button type="button" onClick={() => data.pageRuns(data.report?.nextCursor ?? null)} disabled={data.loading}>Next observations</button>}
      </div>}
      {run && <>
        <div className="vx-latency-toolbar">
          <label>Observation <select value={run.id} onChange={event => data.selectRun(event.target.value)} disabled={data.loading}>
            {data.report?.runs.map(value => <option key={value.id} value={value.id}>{name(value.participantId)} · {value.anchorUtc}</option>)}
          </select></label>
          <button type="button" onClick={data.reload} disabled={data.loading}>Refresh diagnostics</button>
        </div>
        <p className="vx-latency-description">{String(run.profile.provider)} · {String(run.profile.model)} · {reason(String(run.profile.inference_source))}. Coverage: {reason(run.coverage.status)}{run.coverage.reasons.length > 0 ? ` (${run.coverage.reasons.map(reason).join(", ")})` : ""}. {run.coverage.storedTurns} stored turns, {run.coverage.pendingTurns} pending.</p>
        <div className="vx-latency-table-scroll" tabIndex={0} role="region" aria-label="Per-turn latency, scroll for more stages"><table aria-label="Per-turn latency">
          <thead><tr><th scope="col">Human turn</th>{stages.map(([key, label]) => <th scope="col" key={key}>{label}</th>)}<th scope="col">Evidence</th></tr></thead>
          <tbody>{data.turns?.runId === run.id && data.turns.turns.map((turn, index) => <TurnRow key={`${run.id}:${turn.turnId}`} turn={turn} index={index}
            onTranscript={(() => {
              const message = messages.find(item => item.turnId === turn.turnId && item.participantId === run.participantId);
              return message && onTranscript ? () => onTranscript(message.id) : undefined;
            })()} />)}</tbody>
        </table></div>
        {!data.loading && data.turns?.runId === run.id && data.turns.turns.length === 0 && <p>{data.turnCursor ? "No more turns on this page." : "No turn summaries in this observation yet."}</p>}
        <div className="vx-latency-toolbar">
          {data.turnCursor && <button type="button" onClick={() => data.pageTurns(null)} disabled={data.loading}>First turns</button>}
          {data.turns?.nextCursor && <button type="button" onClick={() => data.pageTurns(data.turns?.nextCursor ?? null)} disabled={data.loading}>Next turns</button>}
        </div>
      </>}
      {data.report && data.report.summary.length > 0 && <details className="vx-latency-summary"><summary>Whole-call summaries</summary>
        <p>All collected turns, grouped by provider and observation profile. Excluded samples do not contribute to percentiles.</p>
        {data.report.summary.filter(value => value.metric === "speech_end_to_provider_end").map((value, index) => <div key={index}>
          <p>{String(value.profile.provider)} · {String(value.profile.model)} · {reason(String(value.profile.inference_source))}: median {ms(value.p50Us)}, p95 {ms(value.p95Us)} · {value.validCount} valid, {value.excludedCount} excluded.</p>
          <details><summary>Observation profile {index + 1}</summary><dl>{Object.entries(value.profile).map(([key, setting]) => <div key={key}><dt>{reason(key)}</dt><dd>{typeof setting === "object" ? JSON.stringify(setting) : String(setting)}</dd></div>)}</dl></details>
        </div>)}
      </details>}
    </div>}
  </section>;
}
