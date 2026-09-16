# Debug console metrics

Status: design investigation completed 2026-09-16; attributed timing and client-statistics
projections are not implemented.

This document defines which metrics in the debug-console prototype are useful, what each one
means, and how Vxpipe can obtain it without presenting unrelated measurements under a familiar
label. It distinguishes the current platform's aggregate operational telemetry, call-attributed
usage observations, call lifecycle facts, and browser WebRTC statistics.

## Findings

The prototype's main metric families are useful. The platform already has most of the raw
boundaries, but it cannot currently deliver most latency values to a message hover or a call's
Metrics tab:

- Model request duration, first non-empty model output, and TTS request-to-first-decoded-audio
  are measured with a monotonic clock by
  [`Vxpipe.CallEngine.Telemetry`](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/telemetry.ex).
  Those events deliberately omit call, participant, turn, and attempt identity. The Console
  reporter aggregates them by provider. Aggregate values must not be assigned back to a call.
- Model token counts, TTS input characters/generated-audio duration, and STT recognized-audio
  duration are private `usage_observed` facts. Model and TTS observations have authoritative turn
  attribution. STT observations currently identify a participant and service interval, but not an
  application turn. These values are available to authorized live inspection and persisted call
  history; they are not projected to `@vxpipe/core` today.
- Participant-turn, generated-output, delivery-started, and agent-turn-terminal facts share a
  correlation ID and source timestamps. They can support historical turn intervals. New live
  measurements should use monotonic duration tracking at the owning runtime boundary rather than
  depend on subtraction of wall-clock timestamps.
- Neither the gateway nor `@vxpipe/core` currently polls browser `RTCPeerConnection` statistics.
  WebRTC network RTT, jitter, and packet-loss values therefore need a client media-adapter
  projection. Browser network RTT does not prove that a person heard audio.
- Input and output guardrails are not implemented capabilities. Their groups remain absent until
  those runtime steps exist and expose the same attributed timing contract.

The current debug packages are fixture-backed. No real adapter currently supplies any prototype
metric to them.

## Message metric contract

Every message-hover measurement belongs to one authoritative output turn. A model or TTS value
also carries its capability attempt ID because a turn may invoke a model or synthesizer more than
once. The UI omits a value when its boundary, attribution, or required provider usage is absent.

| Prototype measurement | Definition | How to obtain it | Current state |
| --- | --- | --- | --- |
| Response duration | Committed participant input to terminal agent turn. Spoken turns include output playback; interrupted and failed turns retain their outcome. | Track both boundaries in Room Authority with the same correlation ID and a monotonic clock. Existing correlated source timestamps can support explicitly labeled historical values. | Derivable, but no metric projection exists. `Turn duration` is the clearer eventual UI label. |
| TTFT | Model request dispatch to the first non-empty text-bearing model output for one model attempt. Tool-only attempts can remain unavailable. | Preserve the existing `model_first_token` duration beside call, participant, turn, activation, and attempt identity. ReqLLM also exposes time-to-first-content-chunk, but Vxpipe's owning request boundary remains the canonical measurement. | Measured only as an anonymous provider aggregate. |
| TPOT | Average time per token after first output: `(last output - first output) / (output tokens - 1)`. | Join attributed first/last text-output timing with provider-reported output tokens for the same attempt. Require more than one output token and a non-negative interval. Mark provenance as derived. | Derivable after attributed model timings are added. It is an average, not per-token tracing. |
| TPS | Output-token generation rate after first output: `(output tokens - 1) / (last output - first output)` in seconds. | Use the same attempt-local inputs as TPOT. Require more than one output token and a positive interval. Mark provenance as derived. | Derivable after attributed model timings are added. |
| Time to first audio | TTS request dispatch to the first decoded provider audio frame for one synthesis attempt. | Preserve the existing `tts_first_audio` duration with call, participant, turn, activation, and attempt identity. | Measured only as an anonymous provider aggregate. The prototype's current `Audio-to-first-audio` label describes this value incorrectly. |
| RTF | TTS synthesis wall duration divided by generated audio duration for the same attempt. Values below 1 mean synthesis was faster than realtime. | Record monotonic TTS request-to-terminal duration and divide it by the existing locally measured generated-audio duration. Require a positive audio duration. | Partially available; generated audio duration exists, synthesis wall duration does not. |
| Audio-to-first-audio (A2FA) | Committed audio-input turn to the first server-confirmed output playback start for the correlated agent turn. | Track `ParticipantTurnCompleted` to `AgentSpeechStarted` with the shared correlation ID. Record it as a whole-turn voice metric. | Derivable. It is not the existing TTS first-audio telemetry and does not prove remote audibility. |

For a turn with tools or several model attempts, the hover should show attempt values separately or
use an explicitly named aggregate. It must not silently assign the final request's TTFT to the
whole turn or combine attempt durations across overlapping work.

## Metrics tab contract

The four UI scopes remain useful. The projection groups measurements only after preserving their
original call, participant, capability, turn, attempt, source, unit, outcome, and clock domain.

| Scope | Useful content | Source and work required |
| --- | --- | --- |
| Room | Call duration; completed/failed/interrupted turn counts; turn-duration and A2FA summaries when samples exist. | Derive counts and summaries from attributed call metrics and lifecycle facts. Do not show percentiles for an empty sample set. |
| Room capability | Request/session counts, failures, and latency summaries for LLM, STT, TTS, and implemented guardrails; token/audio/character totals where meaningful. | Aggregate attributed attempt/session observations within this call. Keep providers and clock domains distinguishable. |
| Participant | Turn counts and browser connection RTT, jitter, and packet-loss measurements when a connection exposes them. | Facts provide turn attribution. A bounded `getStats()` poller in the client media adapter supplies WebRTC values and stops on disconnect. |
| Participant capability | Per-participant model TTFT/duration/tokens/TPS/TPOT, STT final-transcript latency and recognized-audio duration, and TTS time-to-first-audio/RTF/generated-audio duration. | Combine attributed call metrics with existing usage observations. STT latency needs new instrumentation and turn attribution. |

The existing tab fixture has these specific results:

- **First model token**, **First audio**, and **Model output** make sense. Model output tokens are
  already provider-reported and call-attributed. The two latency values need attributed copies of
  existing local measurements.
- **Round-trip time** makes sense as a participant connection metric sourced from browser WebRTC
  statistics. It is not a backend response time.
- **Speech recognition** makes sense only when renamed/defined as final-transcript latency. The
  existing provider-reported recognized-audio duration is usage, not latency, and cannot supply
  that value. A participant-capability value may also roll up to a room-capability summary.
- **Remote playback** should be removed. No current browser or server boundary proves that audio
  reached a listener's speakers or ears. Network receive/jitter-buffer statistics may be shown
  under their own names.

## Backend and client work

1. Add a call-metric observation contract separate from billing usage. Include a stable metric
   code, value/unit, source/provenance, call and room incarnation, participant/activation, turn,
   capability attempt or service interval, outcome, observed time, and boundary version.
2. In the model coordinator, emit call-scoped request duration plus first- and last-text-output
   offsets from the same monotonic start and with the same attempt identity used by
   `ModelProjection`. Continue emitting the existing identity-free operational telemetry.
3. In TTS, retain monotonic request start through terminal completion and emit duration plus
   first-decoded-audio duration with the `TextToSpeechAttempt` identity. Reuse its generated-audio
   duration to derive RTF.
4. In Room Authority, track correlated input-commit, first generated output, first playback start,
   and terminal turn boundaries. Emit whole-turn duration and A2FA without treating output-sink
   acceptance as remote audibility.
5. For STT, define final-transcript latency against the submitted audio timeline. Map the
   provider's final audio-window boundary to a local monotonic point, then measure receipt of the
   final transcript. Add utterance/turn attribution; keep recognized-audio duration as a separate
   usage value.
6. Project safe metric observations through the existing bounded, tenant-authorized live/history
   inspection path. If the debug seat consumes them over RTVI, use a versioned `vxpipe.metrics`
   `server-message` envelope available only to that authorized projection; do not publish private
   usage facts to ordinary participants.
7. Add stable metric codes, attempt/turn identity, provenance, outcome, and availability to the
   Core normalized contract. React continues to render only normalized values.
8. Add bounded WebRTC statistics polling to the media adapter. Retain the selected candidate-pair
   RTT and relevant inbound/outbound audio statistics with browser provenance and release polling
   on disconnect.
9. Derive TPOT, TPS, RTF, and tab aggregates only after their inputs share the required identity
   and compatible clock boundary. Keep raw observations available so aggregation rules can evolve.

## Rejected substitutions

- Streaming text chunks are not token boundaries and cannot provide TPOT or token counts.
- Recognized audio duration is not speech-recognition latency.
- TTS request-to-first-decoded-audio is not end-to-end A2FA.
- Output-sink start and WebRTC packet receipt do not prove remote playback.
- Provider-wide telemetry aggregates cannot be attached to an individual call or message.
- Wall-clock subtraction across browser and server observations is not a valid latency measure.

## Verification evidence

The investigation traced:

- model and TTS operational durations in `Vxpipe.CallEngine.Telemetry` and their provider-only
  aggregation in `Vxpipe.Console.TelemetryReporter`;
- provider-reported model tokens in `Vxpipe.CallEngine.Usage.ModelProjection`;
- TTS characters/audio duration in `Vxpipe.CallEngine.Usage.TextToSpeechAttempt`;
- STT recognized-audio duration and service-interval attribution in
  `Vxpipe.CallEngine.Usage.SpeechToTextProjection`;
- correlated input/output/playback facts in `Vxpipe.CallEngine.RoomAuthority.InputTurns`,
  `Vxpipe.CallEngine.RoomAuthority.AgentOutput`, and `Vxpipe.CallEngine.Archive.EventProjection`;
- the absence of a metrics projection in `Vxpipe.Gateway.RTVI.Codec` and the current Core media
  adapter; and
- ReqLLM's first non-empty content-chunk timing and normalized provider usage support.
