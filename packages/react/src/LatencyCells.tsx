import { useId, useState, type ReactNode } from "react";
import {
  autoUpdate, flip, FloatingFocusManager, FloatingPortal, offset, shift, size,
  useClick, useDismiss, useFloating, useInteractions, useRole,
} from "@floating-ui/react";
import type { LatencyRun, LatencyTurn, Message } from "@vxpipe/core";
import { Info } from "lucide-react";
import { AcousticSegments } from "./AcousticSegments.js";
import { BargeInEvidence } from "./BargeInEvidence.js";
import {
  bargeInLabel, bargeInValues, endOfTurnLabel, endOfTurnValues, formatUs,
  latencyStats, reasonText, vadSource, type LatencyRow,
} from "./latencyRows.js";

/** Click-opened, dismissible evidence panel; hover tooltips cannot hold interactive content. */
function DetailsPopover({ trigger, label, className, title, theme, children }: {
  trigger: ReactNode; label: string; className: string; title: string; theme: "light" | "dark"; children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const headingId = useId();
  const { refs, floatingStyles, context } = useFloating({
    open, onOpenChange: setOpen, placement: "bottom-start", whileElementsMounted: autoUpdate,
    middleware: [offset(6), flip(), shift({ padding: 8 }), size({ padding: 8,
      apply({ availableHeight, elements }) { elements.floating.style.maxHeight = `${Math.max(160, availableHeight)}px`; } })],
  });
  const { getReferenceProps, getFloatingProps } = useInteractions([useClick(context), useDismiss(context), useRole(context, { role: "dialog" })]);
  return <>
    <button type="button" ref={refs.setReference} className={className} aria-label={label} {...getReferenceProps()}>{trigger}</button>
    {open && <FloatingPortal>
      <FloatingFocusManager context={context} modal={false}>
        <div ref={refs.setFloating} className="vx-latency-details" data-vx-theme={theme} style={floatingStyles}
          aria-labelledby={headingId} {...getFloatingProps()}>
          <h3 id={headingId}>{title}</h3>
          {children}
        </div>
      </FloatingFocusManager>
    </FloatingPortal>}
  </>;
}

/** Number and unit styled like the other metric cells. */
function Duration({ us, strong = false }: { us: number; strong?: boolean }) {
  const [number, unit] = formatUs(us).split(" ");
  return <>{strong ? <strong>{number}</strong> : number} <small>{unit}</small></>;
}

export function LatencySummaryCell({ row, label, target }: { row: LatencyRow; label: string; target: string }) {
  const barge = label === bargeInLabel;
  const stats = latencyStats(barge ? bargeInValues(row) : endOfTurnValues(row));
  const noun = barge ? "interruptions" : "turns";
  return <div className="vx-metric-summary" role="group" aria-label={`${label} summary for ${target}`}>
    <div className="vx-metric-summary-group">
      {barge && stats.total === 0 ? <small className="vx-metric-summary-coverage">No interruptions</small> : <>
        <dl>{([["Median", stats.median], ["p95", stats.p95]] as const).map(([name, value]) => <div key={name}>
          <dt>{name}</dt><dd>{value === null ? <span className="vx-metric-unavailable">Unavailable</span> : <Duration us={value} />}</dd>
        </div>)}</dl>
        <small className="vx-metric-summary-coverage">{stats.valid} of {stats.total} {noun} valid</small>
      </>}
      {row.truncated && <small className="vx-metric-summary-coverage">First {row.turns.length} loaded turns</small>}
    </div>
  </div>;
}

function turnValue(turn: LatencyTurn, label: string): { value: number | null; reason?: string } {
  if (label === endOfTurnLabel) {
    const value = turn.durationsUs.speech_end_to_provider_end ?? null;
    return value === null ? { value, reason: reasonText(turn.metricReasons.speech_end_to_provider_end ?? turn.acousticReason) } : { value };
  }
  const entries = turn.bargeIn?.entries ?? [];
  if (!turn.bargeIn) return { value: null, reason: "not recorded" };
  if (entries.length === 0) return { value: null, reason: "no interruption" };
  const stats = latencyStats(entries.map(entry => entry.durationUs));
  if (stats.median !== null) return { value: stats.median, reason: entries.length > 1 ? `median of ${entries.length}` : undefined };
  return { value: null, reason: [...new Set(entries.flatMap(entry => entry.reasons))].map(reasonText).join(", ") || "missing evidence" };
}

const stages = [["provider_to_room", "Dispatch"], ["room_to_first_text", "Response text"], ["text_to_first_audio", "Audio start"]] as const;
const landmarks = {
  acoustic_end: "Estimated speech end", observer_confirmed: "Observer confirmation",
  provider_text_commit: "Transcript committed", provider_end_received: "STT turn ended",
  adapter_end_emitted: "Adapter end", room_turn_completed: "Room accepted turn",
  first_response_text: "Response text ready", first_audio_started: "Audio started", manual_commit_sent: "Manual commit sent",
} as const;

function TurnDetails({ run, turn, name, message, onTranscript }: {
  run: LatencyRun; turn: LatencyTurn; name: (id: string) => string; message?: Message; onTranscript?: (id: string) => void;
}) {
  return <div className="vx-latency-evidence">
    <p className="vx-latency-muted"><span className="vx-latency-source">{vadSource(run)}</span> · <span title={turn.turnId}>{turn.turnId}</span> · Quality: {turn.quality}{turn.acousticReason && ` (${reasonText(turn.acousticReason)})`}</p>
    {message && onTranscript && <button type="button" className="vx-latency-action" onClick={() => onTranscript(message.id)}>View transcript</button>}
    <dl>
      <div><dt>{endOfTurnLabel}</dt><dd>{formatUs(turn.durationsUs.speech_end_to_provider_end)}</dd></div>
      {stages.map(([key, label]) => <div key={key}><dt>{label}</dt><dd>{turn.durationsUs[key] == null ? `Unavailable · ${reasonText(turn.metricReasons[key])}` : formatUs(turn.durationsUs[key])}</dd></div>)}
      <div><dt>Speech end to audio start</dt><dd>{formatUs(turn.durationsUs.speech_end_to_first_audio)}</dd></div>
    </dl>
    <p className="vx-latency-muted">Landmarks are offsets from this observation’s clock origin. Audio started means acknowledged server egress, not remote hearing. Missing stages are not zero latency.</p>
    <dl>{Object.entries(landmarks).map(([key, label]) => <div key={key}><dt>{label}</dt><dd>{formatUs(turn.landmarksUs[key as keyof typeof landmarks])}</dd></div>)}</dl>
    <p className="vx-latency-muted">Observation started {run.anchorUtc} · Clock: {turn.clockId} · Source: {turn.sourceEpoch} · Revision {turn.revision} · Timing uncertainty: {formatUs(turn.uncertaintyUs)}</p>
    <AcousticSegments evidence={turn.acousticSegments} />
    <BargeInEvidence evidence={turn.bargeIn} name={name} />
  </div>;
}

export function LatencyTurnCells({ row, label, target, participantName, theme, name, messages, onTranscript }: {
  row: LatencyRow; label: string; target: string; participantName: string; theme: "light" | "dark";
  name: (id: string) => string; messages: readonly Message[]; onTranscript?: (id: string) => void;
}) {
  return <div className="vx-metric-observations">
    {row.turns.map(({ run, turn }, index) => {
      const { value, reason } = turnValue(turn, label);
      const shown = value === null ? "Unavailable" : formatUs(value);
      const message = messages.find(item => item.turnId === turn.turnId && item.participantId === run.participantId);
      return <DetailsPopover key={`${run.id}:${turn.turnId}`} theme={theme}
        className={`vx-metric-cell vx-latency-turn-cell${value === null ? " vx-metric-unavailable" : ""}`}
        label={`${label} for ${target}, turn ${index + 1}: ${shown}${reason ? `, ${reason}` : ""}`}
        title={`Turn ${index + 1}, ${participantName}`}
        trigger={<>
          {value === null ? <span aria-hidden="true">—</span> : <Duration us={value} strong />}
          {reason && <small className="vx-latency-reason">{reason}</small>}
        </>}>
        <TurnDetails run={run} turn={turn} name={name} message={message} onTranscript={onTranscript} />
      </DetailsPopover>;
    })}
  </div>;
}

export function LatencyRowDetails({ row, target, participantName, theme }: {
  row: LatencyRow; target: string; participantName: string; theme: "light" | "dark";
}) {
  return <DetailsPopover theme={theme} className="vx-latency-info" label={`Observation details for ${target}`}
    title={`Observation, ${participantName}`} trigger={<Info size={14} aria-hidden="true" />}>
    <div className="vx-latency-evidence">
      <p className="vx-latency-muted">Participant VAD is the participant’s own Silero; Room VAD is Silero run by the room when the participant has none. Provider turn markers are measured separately.</p>
      {row.runs.map(run => <section key={run.id} className="vx-latency-run">
        <dl>
          <div><dt>Source</dt><dd>{vadSource(run)}</dd></div>
          {Object.entries(run.profile).filter(([key]) => key !== "inference_source").map(([key, setting]) => <div key={key}><dt>{reasonText(key)}</dt>
            <dd>{typeof setting === "object" ? JSON.stringify(setting) : String(setting)}</dd></div>)}
          <div><dt>Started</dt><dd>{run.anchorUtc}</dd></div>
          <div><dt>Coverage</dt><dd>{reasonText(run.coverage.status)}{run.coverage.reasons.length > 0 && ` (${run.coverage.reasons.map(reasonText).join(", ")})`}</dd></div>
          <div><dt>Turns</dt><dd>{run.coverage.storedTurns} stored, {run.coverage.pendingTurns} pending</dd></div>
        </dl>
        {run.unattachedSegments !== undefined && <>
          <p className="vx-latency-muted">Speech outside recorded turns is not counted as a turn or latency sample.</p>
          <AcousticSegments evidence={run.unattachedSegments} label="Speech outside recorded turns" />
        </>}
      </section>)}
    </div>
  </DetailsPopover>;
}
