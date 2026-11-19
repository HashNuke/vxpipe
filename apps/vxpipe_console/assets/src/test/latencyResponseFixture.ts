export function latencyResponseFixture() {
  const profile = { provider: "elevenlabs", model: "scribe_v2_realtime", commit_strategy: "vad",
    inference_source: "benchmark_only", vad_model: "silero_v6.2.3", algorithm_version: 1,
    sample_rate: 16000, onset_threshold: 0.5, offset_threshold: 0.35, onset_frames: 4, offset_frames: 16 };
  const counts = { observed_turns: 1, dropped_audio_frames: 0, unmatched_provider_events: 0 };
  return { schema_version: 1, call_id: "call-public-id", next_cursor: null,
    runs: [{ id: "run-one", schema_version: 1, revision: 3, settings_revision: 2, participant_id: "caller",
      connection_id: "connection-one", source_epoch: "source-one", clock_id: "clock-one", profile,
      state: "closed", counts, reasons: [], anchor_utc: "2026-11-19T12:00:00Z",
      heartbeat_at: "2026-11-19T12:00:10Z", closed_at: "2026-11-19T12:00:10Z",
      coverage: { status: "complete", recorded_state: "closed", reasons: [], termination_reasons: ["call_ended"],
        ...counts, stored_turns: 1, pending_turns: 0 } }],
    summary: [{ profile, metric: "provider_to_room", valid_count: 1, excluded_count: 0, p50_us: 20100.5, p95_us: 20100.5 }] };
}
export function latencyTurnsFixture() {
  return { schema_version: 1, call_id: "call-public-id", run_id: "run-one", next_cursor: null,
    turns: [{ run_id: "run-one", turn_id: "turn-one", revision: 4, stt_allocation_id: "stt-one",
      clock_id: "clock-one", source_epoch: "source-one", provider_turn_id: null, response_turn_id: null,
      landmarks_us: { provider_end_received: 100100, room_turn_completed: 120200 },
      durations_us: { provider_to_room: 20100, speech_end_to_provider_end: null },
      metric_reasons: { provider_to_room: null, speech_end_to_provider_end: "missing_evidence" },
      quality: "incomplete", acoustic_reason: null, acoustic_sample: null, uncertainty_us: 32000 }] };
}
