import type { JsonValue } from "./types.js";

export const latencyMetrics = [
  "speech_end_to_provider_end", "observer_confirmation", "commit_to_provider_end",
  "provider_to_adapter", "provider_to_room", "room_to_first_text", "text_to_first_audio",
  "speech_end_to_first_audio", "speech_end_to_manual_commit", "manual_commit_to_provider_end",
] as const;
export type LatencyMetric = typeof latencyMetrics[number];
export const latencyLandmarks = [
  "acoustic_end", "observer_confirmed", "provider_text_commit", "provider_end_received",
  "adapter_end_emitted", "room_turn_completed", "first_response_text", "first_audio_started", "manual_commit_sent",
] as const;
export type LatencyLandmark = typeof latencyLandmarks[number];
export type LatencyProfile = Readonly<Record<string, JsonValue>>;

export interface LatencyCoverage {
  status: "collecting" | "complete" | "incomplete" | "unconfirmed";
  recordedState: "running" | "closed" | "incomplete";
  reasons: readonly string[];
  terminationReasons: readonly string[];
  observedTurns: number;
  storedTurns: number;
  pendingTurns: number;
  droppedAudioFrames: number;
  unmatchedProviderEvents: number;
}
/** Acoustic segments belong to the enclosing run's source/clock, not to a response agent. */
export interface LatencyAcousticSegment {
  epoch: number;
  startSample: number | null;
  endSample: number | null;
  startUs: number | null;
  endUs: number | null;
  startConfirmedUs: number | null;
  endConfirmedUs: number | null;
  uncertaintyUs: number | null;
  reasons: readonly string[];
}
export interface LatencyAcousticSegments {
  version: 1;
  entries: readonly LatencyAcousticSegment[];
  omittedCount: number;
  reasons: readonly string[];
}
export interface LatencyRun {
  id: string;
  revision: number;
  settingsRevision: number;
  participantId: string;
  connectionId: string;
  sourceEpoch: string;
  clockId: string;
  profile: LatencyProfile;
  state: "running" | "closed" | "incomplete";
  anchorUtc: string;
  heartbeatAt: string;
  closedAt: string | null;
  reasons: readonly string[];
  coverage: LatencyCoverage;
  /** Absent/null on legacy reports; an empty evidence object means observed with no segments. */
  unattachedSegments?: LatencyAcousticSegments | null;
}
export interface LatencyTurn {
  runId: string;
  turnId: string;
  revision: number;
  sttAllocationId: string;
  clockId: string;
  sourceEpoch: string;
  providerTurnId: string | null;
  responseTurnId: string | null;
  landmarksUs: Partial<Record<LatencyLandmark, number>>;
  durationsUs: Partial<Record<LatencyMetric, number | null>>;
  metricReasons: Partial<Record<LatencyMetric, string | null>>;
  quality: "available" | "incomplete" | "unavailable";
  acousticReason: string | null;
  acousticSample: number | null;
  uncertaintyUs: number | null;
  acousticSegments?: LatencyAcousticSegments | null;
}
export interface LatencySummary {
  profile: LatencyProfile;
  metric: LatencyMetric;
  validCount: number;
  excludedCount: number;
  p50Us: number | null;
  p95Us: number | null;
}
export interface LatencyReport {
  runs: readonly LatencyRun[];
  summary: readonly LatencySummary[];
  nextCursor: string | null;
}
export interface LatencyTurnPage {
  runId: string;
  turns: readonly LatencyTurn[];
  nextCursor: string | null;
}
/** URLs and authentication are owned by the host. Opening the panel never enables capture. */
export interface LatencyLoader {
  report(cursor: string | null, signal: AbortSignal): Promise<LatencyReport>;
  turns(runId: string, cursor: string | null, signal: AbortSignal): Promise<LatencyTurnPage>;
}

/** Refresh one bounded page without letting late evidence regress a retained row. */
export function mergeLatencyTurns(previous: LatencyTurnPage | undefined, next: LatencyTurnPage): LatencyTurnPage {
  if (!previous || previous.runId !== next.runId) return next;
  const retained = new Map(previous.turns.map(turn => [turn.turnId, turn]));
  return { ...next, turns: next.turns.map(turn => {
    const current = retained.get(turn.turnId);
    return current && current.revision >= turn.revision ? current : turn;
  }) };
}
