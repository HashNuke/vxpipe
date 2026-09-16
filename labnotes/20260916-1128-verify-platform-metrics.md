# Verify platform metrics

## Objective

Check whether the metrics shown in the debug-console message hover and Metrics tab are meaningful,
identify evidence already produced by Vxpipe or its provider libraries, and plan missing backend and
client support without assigning aggregate or unrelated measurements to a call.

## Findings

- The prototype's model and TTS latency families are useful, but current call-engine telemetry is
  intentionally identity-free and aggregated by provider. It cannot feed a call or message UI.
- Model token counts and TTS generated-audio duration already have call/participant/turn/attempt
  attribution in private `usage_observed` facts. STT recognized-audio duration has participant and
  service-interval attribution but no turn identity.
- Correlated participant-turn, output-generation, playback-start and terminal facts provide the
  boundaries for whole-turn duration and A2FA. New live durations should use monotonic tracking.
- ReqLLM records time to the first non-empty content chunk and normalizes provider token usage.
  Chunks are not tokens, so exact per-token timings are unavailable. TPOT/TPS can be attempt-level
  derived averages after attributed request timing and final output-token usage are joined.
- TTS RTF is derivable after adding attributed synthesis wall duration; locally measured generated
  audio duration already exists.
- Final-transcript latency needs STT audio-timeline instrumentation. Recognized-audio duration is
  not a latency substitute.
- Browser WebRTC RTT is meaningful but needs a bounded client media-adapter `getStats()` poller.
  Neither that nor server output-sink acceptance proves remote playback.
- Guardrail metric groups remain absent until those capabilities exist.

## Decisions

- Keep useful target metrics in the design even when backend projection work remains.
- Define TTS time to first audio separately from end-to-end A2FA.
- Remove remote playback as a metric; expose actual network/jitter measurements by their own names.
- Add call-scoped metric observations separately from billing usage and retain existing aggregate
  operational telemetry.
- Project metrics through tenant-authorized bounded inspection. Any RTVI debug-seat projection is
  versioned and does not expose private usage to ordinary participants.

## Evidence

- Source review covered Call Engine telemetry, model/TTS/STT usage projections, Room Authority turn
  events, archive facts, live inspection, the RTVI codec, Core/React contracts and ReqLLM telemetry.
- Durable findings and formulas are recorded in `docs/debug-console-metrics.md` and linked from the
  call-debug-console milestone.
