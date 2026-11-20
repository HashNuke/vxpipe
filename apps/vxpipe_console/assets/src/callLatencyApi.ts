import { latencyLandmarks, latencyMetrics } from "@vxpipe/core";
import type { JsonValue, LatencyAcousticSegment, LatencyAcousticSegments, LatencyBargeIn, LatencyBargeInEntry, LatencyCoverage, LatencyLoader, LatencyProfile, LatencyReport,
  LatencyRun, LatencySummary, LatencyTurn, LatencyTurnPage } from "@vxpipe/core";

type ObjectValue = Record<string, unknown>;
export class CallLatencyResponseError extends Error {
  constructor(message: string, readonly status: number | null = null) {
    super(message); this.name = "CallLatencyResponseError";
  }
}
const invalid = (): never => { throw new CallLatencyResponseError("Latency diagnostics returned malformed data."); };
const object = (value: unknown): ObjectValue =>
  value !== null && typeof value === "object" && !Array.isArray(value) ? value as ObjectValue : invalid();
function text(value: unknown, maximum = 256): string {
  return typeof value === "string" && value.length > 0 && new TextEncoder().encode(value).length <= maximum ? value : invalid();
}
function integer(value: unknown, minimum = 0): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum ? value : invalid();
}
function number(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : invalid();
}
function nullable<T>(value: unknown, decode: (input: unknown) => T): T | null { return value === null ? null : decode(value); }
function member<T extends string>(value: unknown, values: readonly T[]): T {
  return typeof value === "string" && values.includes(value as T) ? value as T : invalid();
}
function instant(value: unknown): string {
  const result = text(value, 64);
  return Number.isFinite(Date.parse(result)) ? result : invalid();
}
function array(value: unknown, maximum = 100): unknown[] {
  return Array.isArray(value) && value.length <= maximum ? value : invalid();
}
function strings(value: unknown): string[] { return array(value, 32).map(item => text(item, 128)); }
function unique<T>(values: T[], key: (value: T) => string): T[] {
  return new Set(values.map(key)).size === values.length ? values : invalid();
}
const states = ["running", "closed", "incomplete"] as const;
const profileKeys = ["provider", "model", "commit_strategy", "inference_source", "vad_model", "algorithm_version",
  "sample_rate", "onset_threshold", "offset_threshold", "onset_frames", "offset_frames", "provider_acknowledgement"];
const acknowledgedKeys = ["model_id", "sample_rate", "audio_format", "commit_strategy", "vad_silence_threshold_secs",
  "vad_threshold", "min_speech_duration_ms", "min_silence_duration_ms", "keepalive_interval_ms"];
function scalar(value: unknown): JsonValue {
  if (typeof value === "string") return text(value);
  if (typeof value === "number") return number(value);
  return invalid();
}
function profile(value: unknown): LatencyProfile {
  const input = object(value);
  if (Object.keys(input).some(key => !profileKeys.includes(key))) return invalid();
  for (const key of ["provider", "model", "vad_model"]) text(input[key]);
  member(input.commit_strategy, ["vad", "manual", "provider_semantic", "unknown"]);
  member(input.inference_source, ["benchmark_only", "operational_reuse"]);
  for (const key of ["algorithm_version", "sample_rate", "onset_frames", "offset_frames"]) integer(input[key], 1);
  for (const key of ["onset_threshold", "offset_threshold"]) if (number(input[key]) > 1) return invalid();
  const result: Record<string, JsonValue> = {};
  for (const [key, setting] of Object.entries(input)) {
    if (key === "provider_acknowledgement") {
      if (setting === null) { result[key] = null; continue; }
      const ack = object(setting);
      if (Object.keys(ack).some(name => !acknowledgedKeys.includes(name))) return invalid();
      result[key] = Object.fromEntries(Object.entries(ack).map(([name, content]) => [name, scalar(content)]));
    } else result[key] = scalar(setting);
  }
  return result;
}
function coverage(value: unknown): LatencyCoverage {
  const input = object(value);
  return { status: member(input.status, ["collecting", "complete", "incomplete", "unconfirmed"]),
    recordedState: member(input.recorded_state, states), reasons: strings(input.reasons), terminationReasons: strings(input.termination_reasons),
    observedTurns: integer(input.observed_turns), storedTurns: integer(input.stored_turns), pendingTurns: integer(input.pending_turns),
    droppedAudioFrames: integer(input.dropped_audio_frames), unmatchedProviderEvents: integer(input.unmatched_provider_events) };
}
function run(value: unknown): LatencyRun {
  const input = object(value);
  if (input.schema_version !== 1) return invalid();
  return { id: text(input.id), revision: integer(input.revision, 1), settingsRevision: integer(input.settings_revision),
    participantId: text(input.participant_id), connectionId: text(input.connection_id), sourceEpoch: text(input.source_epoch),
    clockId: text(input.clock_id), profile: profile(input.profile), state: member(input.state, states),
    anchorUtc: instant(input.anchor_utc), heartbeatAt: instant(input.heartbeat_at), closedAt: nullable(input.closed_at, instant),
    reasons: strings(input.reasons), coverage: coverage(input.coverage), unattachedSegments: acousticSegments(input.unattached_segments) };
}
function summary(value: unknown): LatencySummary {
  const input = object(value);
  const validCount = integer(input.valid_count);
  const p50Us = nullable(input.p50_us, number), p95Us = nullable(input.p95_us, number);
  if ((validCount === 0) !== (p50Us === null) || (validCount === 0) !== (p95Us === null)) return invalid();
  return { profile: profile(input.profile), metric: member(input.metric, latencyMetrics), validCount,
    excludedCount: integer(input.excluded_count), p50Us, p95Us };
}
function mapping<K extends string, V>(value: unknown, keys: readonly K[], decode: (input: unknown) => V): Partial<Record<K, V>> {
  const input = object(value);
  if (Object.keys(input).some(key => !keys.includes(key as K))) return invalid();
  return Object.fromEntries(Object.entries(input).map(([key, content]) => [key, decode(content)])) as Partial<Record<K, V>>;
}
function offset(value: unknown): number {
  const result = integer(value);
  return result <= 604_800_000_000 ? result : invalid();
}
const segmentReasons = ["partial_start", "audio_gap", "inference_reset", "source_changed", "clock_uncertain",
  "ambiguous_boundary", "observer_overloaded", "pending"] as const;
function evidenceReasons(value: unknown, allowed: readonly string[]): string[] {
  return unique(array(value, allowed.length).map(item => member(item, allowed)), item => item);
}
function ordered(first: number | null, last: number | null): boolean {
  return first === null || last === null || first <= last;
}
function acousticSegment(value: unknown): LatencyAcousticSegment {
  const input = object(value);
  const fields = ["epoch", "start_sample", "end_sample", "start_us", "end_us", "start_confirmed_us", "end_confirmed_us", "uncertainty_us", "reasons"];
  if (Object.keys(input).length !== fields.length || Object.keys(input).some(key => !fields.includes(key))) return invalid();
  const segment: LatencyAcousticSegment = {
    epoch: offset(input.epoch), startSample: nullable(input.start_sample, offset), endSample: nullable(input.end_sample, offset),
    startUs: nullable(input.start_us, offset), endUs: nullable(input.end_us, offset),
    startConfirmedUs: nullable(input.start_confirmed_us, offset), endConfirmedUs: nullable(input.end_confirmed_us, offset),
    uncertaintyUs: nullable(input.uncertainty_us, offset), reasons: evidenceReasons(input.reasons, segmentReasons),
  };
  for (const [sample, at, confirmed] of [
    [segment.startSample, segment.startUs, segment.startConfirmedUs],
    [segment.endSample, segment.endUs, segment.endConfirmedUs],
  ] as const) {
    if (sample === null ? at !== null || confirmed !== null : confirmed === null || !ordered(at, confirmed)) return invalid();
  }
  if ((segment.startSample === null && segment.endSample === null) ||
      !ordered(segment.startSample, segment.endSample) || !ordered(segment.startUs, segment.endUs) ||
      !ordered(segment.startConfirmedUs, segment.endConfirmedUs)) return invalid();
  if (segment.reasons.length === 0 && [segment.startSample, segment.endSample, segment.startUs, segment.endUs, segment.uncertaintyUs].includes(null)) return invalid();
  return segment;
}
function acousticSegments(value: unknown): LatencyAcousticSegments | null {
  if (value === undefined || value === null) return null;
  const input = object(value);
  if (input.version !== 1 || Object.keys(input).length !== 4) return invalid();
  const entries = array(input.entries, 32).map(acousticSegment);
  const omittedCount = offset(input.omitted_count);
  const reasons = evidenceReasons(input.reasons, ["segment_limit", ...segmentReasons]);
  if (omittedCount > 0 && !reasons.includes("segment_limit")) return invalid();
  for (const epoch of new Set(entries.map(entry => entry.epoch))) {
    const group = entries.filter(entry => entry.epoch === epoch).sort((a, b) => (a.startSample ?? -1) - (b.startSample ?? -1));
    for (const key of ["startSample", "endSample"] as const) {
      const values = group.map(entry => entry[key]).filter(value => value !== null);
      if (new Set(values).size !== values.length) return invalid();
    }
    for (let index = 1; index < group.length; index++) {
      const previous = group[index - 1]!, next = group[index]!;
      if (previous.endSample === null || next.startSample === null || previous.endSample > next.startSample) return invalid();
    }
  }
  return { version: 1, entries, omittedCount, reasons };
}
const bargeReasons = ["not_playing", "stop_unavailable", "missing_evidence", "ambiguous_boundary", "clock_uncertain",
  "inference_reset", "audio_gap", "source_changed", "observer_overloaded", "before_run", "source_interval_unavailable"] as const;
function bargeInEntry(value: unknown): LatencyBargeInEntry {
  const input = object(value);
  const fields = ["output_id", "agent_participant_id", "response_source_participant_id", "output_connection_id", "response_turn_id", "response_command_id",
    "playback_started_us", "interruption_requested_us", "playback_stopped_us", "speech_started_us", "speech_start_confirmed_us", "speech_start_sample",
    "epoch", "uncertainty_us", "duration_us", "boundary", "reasons"];
  if (Object.keys(input).length !== fields.length || Object.keys(input).some(key => !fields.includes(key))) return invalid();
  const entry: LatencyBargeInEntry = {
    outputId: text(input.output_id), agentParticipantId: text(input.agent_participant_id), responseSourceParticipantId: text(input.response_source_participant_id),
    outputConnectionId: text(input.output_connection_id), responseTurnId: text(input.response_turn_id), responseCommandId: text(input.response_command_id),
    playbackStartedUs: nullable(input.playback_started_us, offset), interruptionRequestedUs: nullable(input.interruption_requested_us, offset),
    playbackStoppedUs: nullable(input.playback_stopped_us, offset), speechStartedUs: nullable(input.speech_started_us, offset),
    speechStartConfirmedUs: nullable(input.speech_start_confirmed_us, offset), speechStartSample: nullable(input.speech_start_sample, offset),
    epoch: nullable(input.epoch, offset), uncertaintyUs: nullable(input.uncertainty_us, offset), durationUs: nullable(input.duration_us, offset),
    boundary: member(input.boundary, ["server_egress"]), reasons: evidenceReasons(input.reasons, bargeReasons),
  };
  if (entry.reasons.length > 0) {
    if (entry.durationUs !== null) return invalid();
  } else {
    if ([entry.playbackStartedUs, entry.interruptionRequestedUs, entry.playbackStoppedUs, entry.speechStartedUs,
      entry.speechStartConfirmedUs, entry.speechStartSample, entry.epoch, entry.uncertaintyUs, entry.durationUs].includes(null) ||
      !ordered(entry.playbackStartedUs, entry.speechStartedUs) || !ordered(entry.speechStartedUs, entry.interruptionRequestedUs) ||
      !ordered(entry.interruptionRequestedUs, entry.playbackStoppedUs) || !ordered(entry.speechStartedUs, entry.speechStartConfirmedUs) ||
      entry.durationUs !== entry.playbackStoppedUs! - entry.speechStartedUs!) return invalid();
  }
  return entry;
}
function bargeIn(value: unknown): LatencyBargeIn | null {
  if (value === undefined || value === null) return null;
  const input = object(value);
  if (input.version !== 1 || Object.keys(input).length !== 4) return invalid();
  const entries = array(input.entries, 32).map(bargeInEntry);
  const omittedCount = offset(input.omitted_count);
  const reasons = evidenceReasons(input.reasons, ["entry_limit"]);
  if ((omittedCount > 0) !== reasons.includes("entry_limit")) return invalid();
  return { version: 1, entries, omittedCount, reasons };
}
function turn(value: unknown, runId: string): LatencyTurn {
  const input = object(value);
  if (input.run_id !== runId) return invalid();
  return { runId, turnId: text(input.turn_id), revision: integer(input.revision, 1), sttAllocationId: text(input.stt_allocation_id),
    clockId: text(input.clock_id, 128), sourceEpoch: text(input.source_epoch), providerTurnId: nullable(input.provider_turn_id, text),
    responseTurnId: nullable(input.response_turn_id, text), landmarksUs: mapping(input.landmarks_us, latencyLandmarks, offset),
    durationsUs: mapping(input.durations_us, latencyMetrics, value => nullable(value, offset)),
    metricReasons: mapping(input.metric_reasons, latencyMetrics, value => nullable(value, text)),
    quality: member(input.quality, ["available", "incomplete", "unavailable"]), acousticReason: nullable(input.acoustic_reason, text),
    acousticSample: nullable(input.acoustic_sample, integer), uncertaintyUs: nullable(input.uncertainty_us, offset), acousticSegments: acousticSegments(input.acoustic_segments), bargeIn: bargeIn(input.barge_in) };
}
function envelope(value: unknown, callId: string): ObjectValue {
  const input = object(value);
  if (input.schema_version !== 1 || input.call_id !== callId) return invalid();
  return input;
}
export function parseLatencyReport(value: unknown, callId: string): LatencyReport {
  const input = envelope(value, callId);
  if (!Array.isArray(input.summary)) return invalid();
  return { runs: unique(array(input.runs).map(run), item => item.id),
    summary: input.summary.map(summary), nextCursor: nullable(input.next_cursor, text) };
}
export function parseLatencyTurns(value: unknown, callId: string, runId: string): LatencyTurnPage {
  const input = envelope(value, callId);
  if (input.run_id !== runId) return invalid();
  return { runId, turns: unique(array(input.turns).map(item => turn(item, runId)), item => item.turnId),
    nextCursor: nullable(input.next_cursor, text) };
}

export function createCallLatencyLoader(tenantKey: string, callId: string, options: {
  fetchImpl?: typeof fetch; onSessionExpired?: () => void;
} = {}): LatencyLoader {
  const fetchImpl = options.fetchImpl ?? fetch;
  const base = `/api/tenants/${encodeURIComponent(tenantKey)}/calls/${encodeURIComponent(callId)}/latency`;
  async function request(path: string, cursor: string | null, signal: AbortSignal) {
    signal.throwIfAborted();
    const query = cursor === null ? "" : `?${new URLSearchParams({ cursor })}`;
    const response = await fetchImpl(path + query, { signal, credentials: "same-origin", cache: "no-store", headers: { accept: "application/json" } });
    signal.throwIfAborted();
    if (!response.ok) {
      if (response.status === 401) options.onSessionExpired?.();
      throw new CallLatencyResponseError("Latency diagnostics could not be loaded.", response.status);
    }
    try {
      const body: unknown = await response.json();
      signal.throwIfAborted();
      return body;
    } catch {
      signal.throwIfAborted();
      return invalid();
    }
  }
  return {
    async report(cursor, signal) { return parseLatencyReport(await request(base, cursor, signal), callId); },
    async turns(runId, cursor, signal) { return parseLatencyTurns(await request(`${base}/runs/${encodeURIComponent(runId)}/turns`, cursor, signal), callId, runId); },
  };
}
