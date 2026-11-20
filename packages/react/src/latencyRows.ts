import type { JsonValue, LatencyRun, LatencyTurn } from "@vxpipe/core";

export const endOfTurnLabel = "End-of-turn detection";
export const bargeInLabel = "Barge-in stop delay";
export const latencyColumnDescriptions: Readonly<Record<string, string>> = {
  [endOfTurnLabel]: "Local Silero estimated speech end to receipt of the STT signal that completes the human turn.",
  [bargeInLabel]: "Local Silero speech onset during agent playback to the server's playback-stop acknowledgement. Not remote hearing.",
};

/** One participant's observation runs that share an identical profile. Profiles are never pooled. */
export interface LatencyRow {
  key: string;
  participantId: string;
  profile: LatencyRun["profile"];
  runs: LatencyRun[];
  turns: { run: LatencyRun; turn: LatencyTurn }[];
  truncated: boolean;
}

/** A profile cohort is its complete content, independent of JSON key order. */
export function profileIdentity(value: JsonValue): string {
  if (Array.isArray(value)) return `[${value.map(profileIdentity).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value).sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)
      .map(([key, entry]) => `${JSON.stringify(key)}:${profileIdentity(entry)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function latencyRows(runs: readonly LatencyRun[], turns: ReadonlyMap<string, readonly LatencyTurn[]>,
  truncatedRuns: ReadonlySet<string>): LatencyRow[] {
  const rows = new Map<string, LatencyRow>();
  for (const run of runs) {
    const key = `vad:${run.participantId}:${profileIdentity(run.profile)}`;
    const row = rows.get(key) ?? { key, participantId: run.participantId, profile: run.profile, runs: [], turns: [], truncated: false };
    row.runs.push(run);
    row.turns.push(...(turns.get(run.id) ?? []).map(turn => ({ run, turn })));
    row.truncated ||= truncatedRuns.has(run.id);
    rows.set(key, row);
  }
  return [...rows.values()];
}

export interface LatencyStats { median: number | null; p95: number | null; valid: number; total: number }

export function latencyStats(values: readonly (number | null | undefined)[]): LatencyStats {
  const valid = values.flatMap(value => typeof value === "number" && Number.isFinite(value) ? [value] : [])
    .sort((left, right) => left - right);
  if (valid.length === 0) return { median: null, p95: null, valid: 0, total: values.length };
  const middle = Math.floor(valid.length / 2);
  const median = valid.length % 2 === 0 ? (valid[middle - 1]! + valid[middle]!) / 2 : valid[middle]!;
  const p95 = valid[Math.max(0, Math.ceil(valid.length * 0.95) - 1)]!;
  return { median, p95, valid: valid.length, total: values.length };
}

export function endOfTurnValues(row: LatencyRow) {
  return row.turns.map(({ turn }) => turn.durationsUs.speech_end_to_provider_end ?? null);
}

export function bargeInValues(row: LatencyRow) {
  return row.turns.flatMap(({ turn }) => turn.bargeIn?.entries.map(entry => entry.durationUs) ?? []);
}

/** Microseconds to a display string; positive sub-millisecond values never read as zero. */
export function formatUs(value: number | null | undefined) {
  if (value == null) return "Unavailable";
  if (value > 0 && value < 1000) return "<1 ms";
  return `${Math.round(value / 1000).toLocaleString()} ms`;
}

/** Which Silero produced the evidence, in operator terms. */
export function vadSource(run: LatencyRun) {
  const source = run.profile.inference_source;
  if (source === "operational_reuse") return "Participant VAD";
  if (source === "benchmark_only") return "Room VAD";
  return typeof source === "string" ? reasonText(source) : "Unknown VAD";
}

export const reasonText = (value: string | null | undefined) => value?.replaceAll("_", " ") ?? "missing evidence";
