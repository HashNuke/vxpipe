import type { LatencyLoader, LatencyReport, LatencyTurnPage } from "@vxpipe/core";

export const latencyReport: LatencyReport = {
  runs: [{ id: "run-one", revision: 2, settingsRevision: 4, participantId: "caller", connectionId: "browser",
    sourceEpoch: "source-one", clockId: "clock-one", state: "incomplete", anchorUtc: "2026-11-19T12:00:00Z",
    heartbeatAt: "2026-11-19T12:01:00Z", closedAt: "2026-11-19T12:01:00Z", reasons: ["partial_start"],
    profile: { provider: "elevenlabs", model: "scribe_v2_realtime", inference_source: "benchmark_only", vad_model: "silero_v6.2.3", sample_rate: 16000 },
    coverage: { status: "incomplete", recordedState: "incomplete", reasons: ["partial_start"], terminationReasons: ["call_ended"],
      observedTurns: 2, storedTurns: 2, pendingTurns: 0, droppedAudioFrames: 0, unmatchedProviderEvents: 0 } }],
  summary: [{ profile: { provider: "elevenlabs", model: "scribe_v2_realtime", inference_source: "benchmark_only" },
    metric: "speech_end_to_provider_end", validCount: 1, excludedCount: 1, p50Us: 425000, p95Us: 425000 }],
  nextCursor: null,
};
export const latencyTurns: LatencyTurnPage = {
  runId: "run-one", nextCursor: null,
  turns: [
    { runId: "run-one", turnId: "turn-one", revision: 2, sttAllocationId: "stt-one", clockId: "clock-one", sourceEpoch: "source-one",
      providerTurnId: "provider-one", responseTurnId: "response-one", quality: "available", acousticReason: null,
      acousticSample: 48000, uncertaintyUs: 32000,
      landmarksUs: { acoustic_end: 3000000, observer_confirmed: 3512000, provider_end_received: 3425000,
        room_turn_completed: 3437000, first_response_text: 3625000, first_audio_started: 3825000 },
      durationsUs: { speech_end_to_provider_end: 425000, provider_to_room: 12000, room_to_first_text: 188000, text_to_first_audio: 200000, speech_end_to_first_audio: 825000 },
      metricReasons: {} },
    { runId: "run-one", turnId: "turn-two", revision: 1, sttAllocationId: "stt-one", clockId: "clock-one", sourceEpoch: "source-one",
      providerTurnId: "provider-two", responseTurnId: null, quality: "incomplete", acousticReason: "partial_start",
      acousticSample: null, uncertaintyUs: null, landmarksUs: { provider_end_received: 7000000, room_turn_completed: 7015000 },
      durationsUs: { speech_end_to_provider_end: null, provider_to_room: 15000, room_to_first_text: null, text_to_first_audio: null },
      metricReasons: { speech_end_to_provider_end: "partial_start", room_to_first_text: "missing_evidence", text_to_first_audio: "missing_evidence" } },
  ],
};
export type LatencyFixtureMode = "available" | "empty" | "unavailable" | "loading" | "denied" | "pending" | "unsupported" | "zero-valid" | "large";
export function createLatencyFixture(mode: LatencyFixtureMode = "available"): LatencyLoader {
  return {
    async report() {
      if (mode === "loading") return new Promise(() => {});
      if (mode === "denied") throw { status: 403 };
      if (mode === "pending") return { ...latencyReport, summary: [], runs: [{ ...latencyReport.runs[0]!, state: "running", closedAt: null, reasons: [], coverage: { ...latencyReport.runs[0]!.coverage, status: "collecting", recordedState: "running", reasons: [], terminationReasons: [], storedTurns: 0, pendingTurns: 2 } }] };
      if (mode === "unsupported") return { ...latencyReport, summary: [], runs: [{ ...latencyReport.runs[0]!, reasons: ["unsupported"], coverage: { ...latencyReport.runs[0]!.coverage, reasons: ["unsupported"], observedTurns: 0, storedTurns: 0, pendingTurns: 0 } }] };
      if (mode === "large") return { ...latencyReport, runs: [{ ...latencyReport.runs[0]!, coverage: { ...latencyReport.runs[0]!.coverage, observedTurns: 200, storedTurns: 200 } }], summary: [{ ...latencyReport.summary[0]!, validCount: 100, excludedCount: 100 }] };
      if (mode === "zero-valid") return { ...latencyReport, summary: [{ ...latencyReport.summary[0]!, validCount: 0, excludedCount: 2, p50Us: null, p95Us: null }] };
      if (mode === "unavailable") throw new Error("Fixture unavailable");
      return mode === "empty" ? { runs: [], summary: [], nextCursor: null } : latencyReport;
    },
    async turns(_runId, cursor) {
      if (mode === "pending" || mode === "unsupported") return { ...latencyTurns, turns: [] };
      if (mode === "large") return { ...latencyTurns, nextCursor: cursor ? null : "turn-100", turns: Array.from({ length: 100 }, (_, index) => ({ ...latencyTurns.turns[index % 2]!, turnId: `turn-${index + 1 + (cursor ? 100 : 0)}` })) };
      if (mode === "zero-valid") return { ...latencyTurns, turns: [{ ...latencyTurns.turns[1]!, turnId: "turn-one" }, latencyTurns.turns[1]!] };
      return latencyTurns;
    },
  };
}
