# Passive speech-end latency benchmark

Status: researched design, not implemented. 2026-11-19. Implementation tasks live
in [Passive call latency diagnostics and readable timelines](../../labnotes/milestones/passive-call-latency-diagnostics.md).

## Decision

Measure estimated acoustic speech end against receipt of the provider evidence
that actually ends the turn using an optional diagnostic observer. Committed
transcript receipt is a separate landmark, not a synonym for turn end. Reuse the pinned Silero model
and PCM conversion primitives, but not the existing conversational `vad` switch.
Persist per-turn summaries in separate call-owned diagnostic tables, outside the
ordinary call timeline; expose a collapsed authorized Latency diagnostics view.

This estimates speech end in the audio received by Vxpipe. It does not establish
the physical microphone endpoint or isolate provider compute from network delay.
Silero is a reproducible acoustic baseline, not human-labelled ground truth.

## Existing implementation evidence

- `Speech.Silero` consumes 16 kHz mono PCM in 512-sample windows (32 ms), with
  independent recurrent state. `Silero.Model` loads the pinned v6.2.3 ONNX asset.
- `Speech.ActivityBoundary` confirms onset after four frames above 0.5 and end
  after sixteen frames below 0.35. End confirmation takes 512 ms of silence; the
  returned sample position is backdated to the start of that silence.
- `Speech.ConversationalSTT` uses local onset to call
  `STTTurnStart.activity_started/1`; it ignores the acoustic end position.
  Detector readiness, buffer limits and failures affect the STT session. It
  resets detector state on provider turn settlement, which is unsuitable for
  delayed independent measurement of the same endpoint.
- `Speech.ActivityRuntime.submit/3` is a synchronous admission call (up to five
  seconds), although inference runs in supervised tasks. It must not be invoked
  from the live media path for optional benchmarking.
- `Media.AudioFrame` already carries media timestamps, sequence numbers,
  `received_at`, connection/participant identity and source epoch.
  `STTActivityPCM` normalizes PCM and its sample timestamp to 16 kHz; the current
  conversational wrapper discards that normalized timestamp.
- `ElevenLabs.ScribeSocket.handle_frame/2` decodes then forwards provider events.
  Add a monotonic receipt timestamp at the earliest application socket boundary,
  before owner mailbox processing, and carry it through diagnostic correlation.
  The existing room `participant_turn_completed` event timestamps later handling.
  Crucially, continuous Scribe accumulates committed segments and settles only
  on an empty provider partial after committed text with no outstanding draft.
  Timestamp that exact end-evidence receipt separately from text commits.
- Both historical manual-commit Scribe and provider-VAD Scribe paths exist.
  Record the effective strategy, model and acknowledged settings per session;
  do not infer them from a missing source-spec option or a current default.

## Measurement contract

For each participant, connection, source epoch and correlated provider turn retain:

1. Estimated last-speech boundary as a media sample offset, plus its mapped
   server monotonic time and mapping uncertainty.
2. Time the observer confirmed that boundary and its inference/queue lag.
3. Provider text-commit receipt, actual turn-end-evidence receipt and adapter
   turn-end emission time.
4. Room turn-completion time, allowing internal scheduling latency to be split
   from provider receipt latency.
5. Explicit manual-commit send time when applicable.

Primary metric: `provider_end_evidence_received - estimated_acoustic_end`.
Separately report `observer_confirmed - estimated_acoustic_end` and
`room_turn_completed - provider_end_evidence_received`.
For manual commit, split acoustic-end-to-commit from commit-to-final-receipt.
These intervals include application transport and network work; they are not
pure STT inference durations.

Do not subtract the observer's confirmation time: that would hide its 512 ms
silence window. Do not mix media sample offsets with UTC timestamps or assume
packet arrival equals microphone capture. Validate the `received_at` clock/unit
for each transport; preserve a per-epoch sample-to-monotonic mapping and expose
jitter/discontinuity uncertainty. No single call-start offset is sufficient when
media gaps, loss or source changes occur.

Maintain a continuous standalone observer stream independently of provider turn
resets. When reusing operational inference, preserve its resets and mark affected
coverage incomplete rather than altering call behavior.
Match the final relevant acoustic segment to each committed turn, allowing
multiple pauses, provider segment commits, overlaps and late observer results.
If correlation is ambiguous, audio is missing, or speech resumes during a
candidate gap, mark the sample ambiguous/incomplete instead of manufacturing a
latency. Report excluded counts alongside p50/p95 and sample count.

## Isolation and rollout

Start with offline processing of an existing isolated participant recording if
it retains usable timing alignment. Availability and alignment of recordings for
the reported call have not been established; archive events alone cannot recover
its acoustic endpoint. Offline VAD needs the original provider receipt trace for
an exact historical comparison, which the current events do not supply. The
required trace distinguishes text-commit receipt from turn-end-evidence receipt.

For future live measurements, copy accepted caller audio to a bounded observer
queue. Never await inference, readiness, persistence or capacity from the live
call. A plain unbounded mailbox is not sufficient. On overflow drop benchmark
data, mark the interval invalid, and reset detector continuity. Do not block,
commit STT input, emit speech control events, interrupt an agent or fail a call.
Use separate supervision and inference capacity; cap CPU/memory and sampled
calls. A separate OS process offers stronger native-runtime failure isolation.
Any live observer has nonzero copy/CPU overhead; demonstrate bounded overhead
instead of promising literally zero interference. Persist timing summaries and
quality flags, not raw audio, by default.

## Rejected alternatives

- Enable existing `vad: true`: changes operational onset behavior and shares
  session readiness/failure handling.
- Use final-transcript/room-turn timestamps alone: excludes the unknown speech
  endpoint and conflates provider receipt with internal processing.
- Enable provider word timestamps as the sole baseline: not independent acoustic
  evidence; current protocol decoder does not support that event type.
- Add a second live STT request: unnecessary cost and a different network path.
- Treat all silence as turn end: conversational pauses are not completed turns.

## Required verification before implementation acceptance

- Red/green boundary tests for sample-time mapping, backdated endpoints, provider
  final arriving before VAD confirmation, resumed speech and multiple segments.
- Failure/overload tests demonstrating identical production turn decisions,
  provider input bytes and commit behavior with the observer on and off.
- Disconnect, source-epoch, packet-gap, observer crash and native timeout tests.
- Replay labelled caller-only audio, including noise/echo and agent overlap;
  quantify endpoint error rather than assuming 32 ms windows imply 32 ms accuracy.
- Controlled on/off load comparisons for CPU, memory, audio drops and response
  latency; small opt-in live trial with diagnostic summaries only.
- Repository completion checks for implementation; Lean lane if production speech
  state-machine behavior is changed. No runtime code changed in this research.

## External sources

- [Silero reference implementation](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py): sample-based endpoints, silence confirmation and padding.
- [ElevenLabs commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies): manual versus provider commit and optional word timestamps.
- [ElevenLabs event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference): committed transcript event semantics.

## Durable reports and display decision

The user approved separate durable diagnostics and later requested timeline cleanup.
Use one run/coverage record plus one revisioned logical row per human turn, with
clock provenance, bounded configuration, null unavailable milestones and quality
reasons. Keep loss/disabled/unsupported states distinct. Retry idempotently through
a separately bounded writer; tenant/incarnation checks and call deletion guard
late writes. Diagnostic availability never changes call/publication completeness.
The initial slice does not alter immutable details exports.

Default conversation/debug views hide usage observations, delivery progress/start/
completion, final recognizer transcript, participant turn start and agent turn
completion behind Technical events. Retain accounting and diagnostic records in
production. Messages, tools, failures and interruptions remain visible. Filtering
is by canonical kind, not labels or logger levels. The milestone owns detailed
query, lifecycle, migration, UI state and acceptance contracts.

## App-settings authority (user clarification)

Passive VAD benchmarking is installation-wide, default-off and enabled only by
the persisted **Installation → Diagnostics → Benchmark using Silero VAD** toggle. Built-in admin and superadmin
browser-session principals alone can change it, enforced on server routes and
domain operations. Keep the existing installation URL operation superadmin-only.
No environment, embedding, call-spec or view option can bypass a disabled setting.

Apply versioned settings to active and new eligible calls without synchronous
per-frame reads. Bound propagation and enabled-cache leases; unknown/expired
authority disables diagnostics without affecting calls. Enable starts a fresh
epoch (mid-turn evidence is incomplete); disable revokes capture and discards
queued audio, while already captured summaries may finish bounded persistence.
The UI distinguishes saved intent from applying/effective state. Existing reports
remain readable under ordinary inspection authorization. Re-enable never bridges
the unobserved interval. The milestone defines tasks and acceptance cases.

## Reuse existing operational inference (user clarification)

If a call already runs Silero, reuse its timestamped probability/sample evidence
through a bounded observer; do not execute the model twice for the same source
audio. Keep diagnostic state separate. Preserve operational admission, resets,
readiness and failure handling; missing evidence yields incomplete measurements,
not a hidden second inference pass. Mark this provenance as operational reuse,
not an independent detector comparison. If operational Silero is absent, run one
isolated benchmark-only stream while the setting is on. Turning it off detaches
only diagnostics and leaves any call-spec Silero running normally.

The toggle lives in a Diagnostics section of the existing Installation page.
Admins may access that section; the installation URL and its operation retain
their existing superadmin-only authorization. Implementation must replace the
whole-page guard with section-specific access and test both roles.
