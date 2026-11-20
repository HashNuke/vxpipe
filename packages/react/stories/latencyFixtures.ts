import type { LatencyBargeIn, LatencyLoader, LatencyReport, LatencyTurnPage } from "@vxpipe/core";

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
export type LatencyFixtureMode = "barge-in" | "barge-in-late" | "participants" | "available" | "empty" | "unavailable" | "loading" | "denied" | "pending" | "unsupported" | "zero-valid" | "large" | "late" | "retry";
export function createLatencyFixture(mode: LatencyFixtureMode = "available", secondParticipantId = "second-caller"): LatencyLoader {
  let reads = 0;
  return {
    async report() {
      reads++;
      if (mode === "barge-in" || mode === "barge-in-late") return { ...latencyReport, summary: [],
        runs: [{ ...latencyReport.runs[0]!, revision: mode === "barge-in-late" && reads === 1 ? 1 : 2,
          coverage: { ...latencyReport.runs[0]!.coverage, observedTurns: mode === "barge-in" ? 3 : 1, storedTurns: mode === "barge-in" ? 3 : 1 } }] };
      if (mode === "participants") return participantReport(secondParticipantId);
      if (mode === "retry" && reads === 1) throw new Error("Fixture temporary outage");
      if (mode === "late" && reads === 1) return { ...latencyReport, summary: [], runs: [{ ...latencyReport.runs[0]!, revision: 1, state: "running", closedAt: null, reasons: [], coverage: { ...latencyReport.runs[0]!.coverage, status: "collecting", recordedState: "running", reasons: [], terminationReasons: [], storedTurns: 1, pendingTurns: 1 } }] };
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
      if (mode === "barge-in" || mode === "barge-in-late") return bargeInTurns(mode === "barge-in-late", reads === 1);
      if (mode === "participants") return participantTurns(_runId);
      if (mode === "late" && reads === 1) return { ...latencyTurns, turns: [{ ...latencyTurns.turns[0]!, revision: 1, quality: "incomplete", acousticReason: "missing_evidence", acousticSample: null, uncertaintyUs: null,
        landmarksUs: { provider_end_received: 3425000, room_turn_completed: 3437000 }, durationsUs: { speech_end_to_provider_end: null, provider_to_room: 12000 }, metricReasons: { speech_end_to_provider_end: "missing_evidence" } }] };
      if (mode === "pending" || mode === "unsupported") return { ...latencyTurns, turns: [] };
      if (mode === "large") return { ...latencyTurns, nextCursor: cursor ? null : "turn-100", turns: Array.from({ length: 100 }, (_, index) => ({ ...latencyTurns.turns[index % 2]!, turnId: `turn-${index + 1 + (cursor ? 100 : 0)}` })) };
      if (mode === "zero-valid") return { ...latencyTurns, turns: [{ ...latencyTurns.turns[1]!, turnId: "turn-one" }, latencyTurns.turns[1]!] };
      return latencyTurns;
    },
  };
}

// One caller input survives a response-agent transfer; a second human owns another source/clock.
const callerSegments = { version: 1 as const, omittedCount: 0, reasons: [], entries: [
  { epoch: 0, startSample: 0, endSample: 16000, startUs: 0, endUs: 1000000,
    startConfirmedUs: 128000, endConfirmedUs: 1512000, uncertaintyUs: 32000, reasons: [] },
  { epoch: 0, startSample: 32000, endSample: 48000, startUs: 2000000, endUs: 3000000,
    startConfirmedUs: 2128000, endConfirmedUs: 3512000, uncertaintyUs: 32000, reasons: [] },
] };
function participantReport(secondParticipantId: string): LatencyReport {
  const caller = { ...latencyReport.runs[0]!, unattachedSegments: { ...callerSegments,
    entries: [{ ...callerSegments.entries[0]!, startSample: 128000, endSample: 144000,
      startUs: 8000000, endUs: 9000000, startConfirmedUs: 8128000, endConfirmedUs: 9512000 }],
    omittedCount: 3, reasons: ["segment_limit"] } };
  const second = { ...caller, id: "run-second", participantId: secondParticipantId, connectionId: "browser-second",
    sourceEpoch: "source-second", clockId: "clock-second", profile: { ...caller.profile, inference_source: "operational_reuse" },
    reasons: ["inference_reset"], coverage: { ...caller.coverage, reasons: ["inference_reset"], observedTurns: 1, storedTurns: 1 },
    unattachedSegments: { version: 1 as const, entries: [], omittedCount: 0, reasons: [] } };
  return { runs: [caller, second], summary: [], nextCursor: null };
}
function participantTurns(runId: string): LatencyTurnPage {
  if (runId === "run-second") return { runId, nextCursor: null, turns: [{ ...latencyTurns.turns[1]!,
    runId, turnId: "second-human-turn", sttAllocationId: "stt-second", sourceEpoch: "source-second", clockId: "clock-second",
    acousticReason: "inference_reset", metricReasons: { ...latencyTurns.turns[1]!.metricReasons, speech_end_to_provider_end: "inference_reset" }, acousticSegments: { version: 1, omittedCount: 0, reasons: ["inference_reset"],
      entries: [{ epoch: 1, startSample: 0, endSample: null, startUs: 0, endUs: null,
        startConfirmedUs: 128000, endConfirmedUs: null, uncertaintyUs: null, reasons: ["inference_reset"] }] } }] };
  return { ...latencyTurns, turns: [
    { ...latencyTurns.turns[0]!, acousticSegments: callerSegments },
    { ...latencyTurns.turns[1]!, responseTurnId: "specialist-response", quality: "available", acousticReason: null,
      acousticSample: 96000, uncertaintyUs: 32000,
      landmarksUs: { acoustic_end: 6000000, observer_confirmed: 6512000, provider_end_received: 7000000,
        room_turn_completed: 7015000, first_response_text: 7200000, first_audio_started: 7400000 },
      durationsUs: { speech_end_to_provider_end: 1000000, provider_to_room: 15000, room_to_first_text: 185000,
        text_to_first_audio: 200000, speech_end_to_first_audio: 1400000 }, metricReasons: {},
      acousticSegments: { ...callerSegments, entries: [{ ...callerSegments.entries[0]!, startSample: 80000, endSample: 96000,
        startUs: 5000000, endUs: 6000000, startConfirmedUs: 5128000, endConfirmedUs: 6512000 }] } },
  ] };
}

const bargeIn: LatencyBargeIn = { version: 1, omittedCount: 0, reasons: [], entries: [{
  outputId: "previous-agent-output", agentParticipantId: "assistant", responseSourceParticipantId: "second-caller",
  outputConnectionId: "browser-second-caller", responseTurnId: "previous-human-turn", responseCommandId: "previous-response-command",
  playbackStartedUs: 1000000, interruptionRequestedUs: 2100000, playbackStoppedUs: 2160000,
  speechStartedUs: 2000000, speechStartConfirmedUs: 2256000, speechStartSample: 32000,
  epoch: 0, uncertaintyUs: 32000, durationUs: 160000, boundary: "server_egress", reasons: [],
}] };
function bargeInTurns(late: boolean, first: boolean): LatencyTurnPage {
  const available = { ...latencyTurns.turns[0]!, bargeIn };
  if (late) return { ...latencyTurns, turns: [{ ...available, revision: first ? 1 : 2,
    bargeIn: first ? { ...bargeIn, entries: [{ ...bargeIn.entries[0]!, speechStartedUs: null,
      speechStartConfirmedUs: null, speechStartSample: null, epoch: null, uncertaintyUs: null, durationUs: null,
      reasons: ["missing_evidence"] }] } : bargeIn }] };
  return { ...latencyTurns, turns: [available,
    { ...latencyTurns.turns[1]!, bargeIn: { ...bargeIn, entries: [{ ...bargeIn.entries[0]!,
      outputId: "ambiguous-output", speechStartedUs: null, speechStartConfirmedUs: null, speechStartSample: null,
      epoch: null, uncertaintyUs: null, durationUs: null, reasons: ["ambiguous_boundary"] }] } },
    { ...latencyTurns.turns[1]!, turnId: "turn-three", bargeIn: { ...bargeIn, entries: [{ ...bargeIn.entries[0]!,
      outputId: "unconfirmed-stop", playbackStoppedUs: null, durationUs: null, reasons: ["stop_unavailable"] }] } },
  ] };
}
