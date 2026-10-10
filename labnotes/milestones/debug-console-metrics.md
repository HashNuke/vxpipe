# Debug console metrics

> Relocated from `docs/debug-console-metrics.md` on 2026-10-09. First recorded source commit: `e6ba728d1718` (2026-09-16T11:34:23+07:00).
> Supporting plan/evidence companion. [call-debug-console](call-debug-console.md) owns current scope, implementation checklists and acceptance; [the index](index.md) owns order. This is not a new independently ordered milestone.
> This is the approved investigation/design companion. Attributed client metrics remain implementation-pending in the owner. Prototype values and existing provider aggregates do not establish per-call metrics, browser playback evidence or new supported capabilities.

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

- Agent-session request duration, its first non-empty output, and TTS
  request-to-first-decoded-audio are measured with a monotonic clock by
  [`Vxpipe.CallEngine.Telemetry`](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/telemetry.ex).
  Those events deliberately omit call, participant, turn, and attempt identity. The Console
  reporter aggregates them by provider. One agent-session request may contain multiple provider
  model attempts and tool calls, so these model measurements cannot be relabeled as attempt TTFT or
  joined to attempt usage. Aggregate values must not be assigned back to a call.
- Model token counts, TTS input characters/generated-audio duration, and STT recognized-audio
  duration are private `usage_observed` facts. Model and TTS observations have authoritative turn
  attribution. STT observations currently identify a participant and service interval, but not an
  application turn. These values are available to authorized live inspection and persisted call
  history; they are not projected to `@vxpipe/core` today.
- Participant-turn, generated-output, delivery-started, and agent-turn-terminal facts often share
  a correlation ID and source timestamps. Greetings and tool continuations have different trigger
  identities, so a universal turn metric also needs trigger kind, command/connection identity, and
  origin links. New live measurements should use monotonic duration tracking at the owning runtime
  boundary rather than depend on subtraction of wall-clock timestamps.
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
| Response duration | Accepted turn trigger to terminal agent turn. Spoken turns include server audio-egress completion; interrupted and failed turns retain their outcome. Trigger kind distinguishes participant input, greeting, and continuation. | Track both boundaries in Room Authority with command/connection identity, origin links, and a monotonic clock. Existing correlated source timestamps can support explicitly labeled historical values only when both matching boundaries exist. | Partly derivable, but no universal trigger contract or metric projection exists. `Turn duration` is the clearer UI label. |
| TTFT | One provider model attempt's dispatch to its first non-empty visible-text output. Tool-only attempts remain unavailable for this metric. | Instrument attempt dispatch/first visible text in Agent Runtime where the same `UsageRounds` attempt identity is available. ReqLLM's first-content-chunk measurement also fires for a tool call and is not a drop-in TTFT. | Not measured per attempt. Existing model telemetry spans the larger agent-session request. |
| TPOT | Average time per matching generated token after the first token: `(last token - first token) / (matching output tokens - 1)`. | Derive only when one provider contract supplies timing and token counts for the same attempt and token population. Require more than one matching token and a non-negative interval. Mark provenance as derived. | Conditionally derivable. Current visible-text timing cannot be joined safely to normalized output tokens that may include hidden reasoning or tool tokens. |
| TPS | Decode-token rate using the exact same valid inputs as TPOT. Request throughput (`reported output tokens / request duration`) is a separate metric and must be named as such. | Use TPOT's reciprocal only when timing and token population match. Preserve the provider's token categories and denominator definition. | Conditionally derivable; omit it when token semantics do not match. |
| Time to first audio | TTS request dispatch to the first decoded provider audio frame for one synthesis attempt. | Preserve the existing `tts_first_audio` duration with call, participant, turn, activation, and attempt identity. | Measured only as an anonymous provider aggregate. The prototype's current `Audio-to-first-audio` label describes this value incorrectly. |
| RTF | Locally observed TTS synthesis duration divided by generated audio duration for the same attempt. Values below 1 mean observed production was faster than realtime. | Stop the numerator at provider synthesis completion, before playback drains, and divide by the existing generated-audio duration. Require a positive audio duration. Record that transport and local consumption backpressure may affect the numerator. | Partially available; generated audio duration exists, an attempt-terminal synthesis duration does not. |
| Audio-to-first-audio (A2FA) | Authoritative caller speech end to the first server audio egress for the correlated agent turn. | Retain/map the STT/VAD speech-end position onto a local monotonic audio timeline and correlate it to the first egress event for the exact output turn. | Needs new speech-end instrumentation. `ParticipantTurnCompleted` occurs after final STT and would omit endpointing/recognition latency; `AgentSpeechStarted` is server egress, not browser playback. |

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
| Participant | Turn counts and browser connection RTT, jitter, and packet-loss measurements when a connection exposes them. | Facts provide turn attribution. A bounded `getStats()` poller supplies statistics only for the local peer connection and stops on disconnect; remote participants require explicit reporting or separately labeled server observations. |
| Participant capability | Per-participant model TTFT/duration/tokens/TPS/TPOT, STT final-transcript latency and recognized-audio duration, and TTS time-to-first-audio/RTF/generated-audio duration. | Combine attributed call metrics with existing usage observations. STT latency needs new instrumentation and turn attribution. |

The existing tab fixture has these specific results:

- **TTFT**, **Time to first audio**, and provider-reported **Input tokens**, **Output tokens**, and
  **Cached tokens** make sense. Token categories remain separate and call-attributed. The two
  latency values need attempt-attributed local measurements at the corrected boundaries.
- **Round-trip time** makes sense as a participant connection metric sourced from the selected ICE
  candidate pair's `currentRoundTripTime`. It is a latest STUN RTT for the browser's own peer
  connection, not a backend response time or a measurement for every participant.
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
2. In Agent Runtime's provider-generation boundary, emit call-scoped attempt dispatch, first
   visible text, last compatible token/output, and terminal timing with the exact `UsageRounds`
   attempt identity used by `ModelProjection`. Do not attach the coordinator's larger
   agent-session telemetry to a provider attempt. Continue emitting existing operational telemetry.
3. In TTS, retain monotonic request start through terminal completion and emit duration plus
   first-decoded-audio duration with the `TextToSpeechAttempt` identity. Reuse its generated-audio
   duration to derive RTF.
4. In Room Authority, track trigger acceptance, first generated output, first server egress, and
   terminal turn boundaries. Preserve trigger kind plus command, connection, continuation origin,
   and tool identities so greetings and continuations do not acquire fabricated input metrics.
5. For STT, retain a suitable last-word or VAD speech-end position and map the submitted audio
   timeline to local monotonic time across buffering, gaps, and session resets. Measure speech-end
   to final transcript receipt, preserve the finalization trigger, and add utterance/turn
   attribution. Provider audio-window duration remains separate usage and its window end must not
   be assumed to equal speech end.
6. Project safe metric observations through the existing bounded, tenant-authorized live/history
   inspection path. If the debug seat consumes them over RTVI, use a versioned `vxpipe.metrics`
   `server-message` envelope available only to that authorized projection; do not publish private
   usage facts to ordinary participants.
7. Add stable metric codes, attempt/turn identity, provenance, outcome, and availability to the
   Core normalized contract. React continues to render only normalized values.
8. Add bounded WebRTC statistics polling to the media adapter. Retain allowlisted numeric fields,
   observation age, selected candidate-pair RTT and relevant inbound/outbound audio statistics with
   browser provenance. Rebind on connection changes and release polling on disconnect.
9. Derive TPOT, TPS, RTF, and tab aggregates only after their inputs share exact identity, semantic
   population and compatible clock boundaries. Preserve provider token categories. Aggregate
   cumulative usage once, label summary statistic/sample count/coverage, and use weighted RTF when
   aggregating attempts. Keep outcomes and missing samples distinguishable.

## Rejected substitutions

- Streaming text chunks are not token boundaries. Normalized output tokens may include reasoning or
  tool tokens, so they cannot automatically provide TPOT/TPS for visible text.
- Recognized audio duration is not speech-recognition latency.
- TTS request-to-first-decoded-audio is not end-to-end A2FA.
- Output-sink start and WebRTC packet receipt do not prove remote playback.
- Provider-wide telemetry aggregates cannot be attached to an individual call or message.
- Wall-clock subtraction across browser and server observations is not a valid latency measure.
- ReqLLM's first content chunk may be a tool call and is not automatically visible-text TTFT.
- A final duration, RTF, TPOT, or TPS is not available while the required attempt/turn is streaming.

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

An independent GPT-6 Astra xhigh review then traced the attempt boundaries through
`ActiveRequest`, `RequestRunner`, and `UsageRounds`; checked provider token normalization, STT audio
windows, WebRTC egress, backpressure, greetings and continuations; and identified the corrected
contracts above. The prototype fixture must use internally consistent values and omit final metrics
from an active streaming turn.
