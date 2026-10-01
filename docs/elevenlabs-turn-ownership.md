# ElevenLabs input turn ownership

Status: Historical feasibility proposal, updated 2026-10-01. The
[allocation-owned session checkpoint](elevenlabs-stt-session.md) now implements
and admits the STT-only local acoustic composition and passes its selected
two-turn live case. Scoped services, compiled room turns and Console STT
integration now have local acceptance; configured-service live room acceptance
remains pending. The investigation below records earlier evidence
and rejected native-VAD shortcuts; it is not the current implementation checklist.

The user-approved 2026-10-01 milestone scope is ElevenLabs realtime STT and TTS.
Hosted-agent STS is deferred; this proposal addresses caller STT only.

## Realtime scope and native VAD first

The user's scope clarification selects Scribe Realtime or another suitable
ElevenLabs realtime model. Batch recognition does not satisfy this milestone.
Assess `scribe_v2_realtime` with `commit_strategy=vad` before selecting a local
detector or changing shared contracts. The
[commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
documents server speech/silence detection and automatic segment commits after
the configured silence threshold. This is acoustic silence endpointing, not a
documented semantic end-of-thought signal.

Two requirements need separate evidence:

- **Turn end:** determine whether VAD-mode commits reliably identify silence
  endpoints, including uninterrupted speech and long input. The guide documents
  automatic approximately 36-second commits under manual mode. It does not
  establish their behavior under VAD mode; do not assume either that they occur
  there or that every VAD-mode segment is a complete user turn.
- **Speech start:** the current
  [public event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
  documents partial/committed transcripts but no explicit activity-start event.
  A first partial is insufficient evidence for the room's speech-start/barge-in
  contract. Native endpointing alone does not settle that separate requirement.

The separately selected short VAD live case passes on 2026-10-01: one test,
zero failures, 6.6 seconds, seed 205077. It exercises VAD mode with the existing
committed speech fixture and bounded paced silence, asserting stable final text
without sending a manual commit. This is new VAD-mode evidence, not a reason to
repeat the already passing manual transcription probe. A short passing case
cannot prove long uninterrupted-input behavior or manufacture speech-start.
Resolve the long-input contract from primary sources before authorizing a larger
paid matrix; any such experiment needs ordered accepted-sample/message evidence.

### Long VAD observation — 2026-10-01

One separately selected long-input experiment passes: one test, zero failures,
44.0 seconds, seed 364893. It removes the public fixture's known two-second
silence tail, repeats the remaining phrase nineteen times (41.04 seconds), then
sends two seconds of zero PCM. It sends no manual commit. Ordered observations
record two committed segments: one during the repeated-speech input phase at
36,000 ms of accepted client audio, and one during the silence phase at
43,040 ms. Both preserve the known public-fixture word.

Receipt position is not a server processed-through cursor or a commit reason.
Phrase repetition is a protocol experiment, not continuous natural speech or
an acoustic quality corpus. The first observation is consistent with the
documented buffer limit also affecting VAD mode, but does not establish its
cause. It does not provide enough evidence to treat every VAD commit as an
authoritative silence endpoint. The long-input admission gate remains open.
See [experiment evidence](../labnotes/20261001-0102-scribe-long-vad.md).

The local-onset/native-commit shortcut therefore remains inadmissible. Evaluate
controlled manual segment boundaries separately from acoustic turn ownership:
cap submitted audio below automatic-commit limits, allow only one outstanding
commit, and stop submitting new audio until its segment is settled. Verify
empty/unrecognized input and early or delayed segments explicitly. A deadline
must fail the allocation rather than invent a final transcript. This is a
candidate protocol, not an approved finalization guarantee or implemented STT.

### Controlled manual recognition assembly — 2026-10-01

`ScribeTurn` now owns cumulative recognition for an opaque, locally supplied
caller turn. It caps each manual segment at twenty seconds of submitted PCM,
accepts only one outstanding commit, and retains at most the remainder of one
already accepted chunk. Later input is rejected as busy without acceptance.
Partials replace only their current segment; duplicate and empty partials do
not publish additional events. Committed text extends a bounded stable prefix.
An intermediate segment does not end the turn. A supplied acoustic endpoint
seals input; final turn text waits for all retained audio and requested segment
settlement. Unexpected segments and oversized text fail safely.

Eighteen focused turn/codec/socket checks pass, including local transport.
One separately selected manual wire case submits 23.6 seconds, waits for the
twenty-second commit before resuming audio, then settles the supplied endpoint.
It passes in 24.9 seconds, seed 512880: two segment settlements, one cumulative
turn end and the known public-fixture word. The test supplies its boundary; it
does not classify acoustic activity or establish conversational room readiness.
See [implementation evidence](../labnotes/20261001-0125-scribe-controlled-segments.md).

This supports a serialized recognition context instead of requiring a separate
connection for each turn. The future supervised owner must correlate pending
turns, bound queued PCM, enforce commit deadlines and reset across privacy
intervals. Empty or missing settlement still needs explicit failure checks.
No STT capability or contract amendment is admitted by this helper alone.

The preparation codec now accepts only the explicit `:manual`/`:vad` strategies
and checks any returned commit-strategy acknowledgement against the requested
mode. Its socket carries that expected mode privately. Nine focused offline
ExUnit checks pass after four new checks first fail, including mismatch rejection
and safe credential inspection. This is configuration/codec evidence only, not
an integrated socket or provider/room acceptance result.

### Fixed VAD probe profile — 2026-10-01

The preparation now sends the four explicit values shown in the provider's
[commit-strategy example](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies),
rather than depending on undocumented or changing defaults:

| Native setting | Fixed value |
| --- | --- |
| `vad_silence_threshold_secs` | 1.5 seconds |
| `vad_threshold` | 0.4 |
| `min_speech_duration_ms` | 100 ms |
| `min_silence_duration_ms` | 100 ms |

Manual mode sends none of these settings. The VAD acknowledgement rejects
conflicting values when echoed; individual echo fields remain optional as in the
[official SDK configuration type](https://github.com/elevenlabs/elevenlabs-js/blob/main/src/wrapper/realtime/connection.ts).
These fixed values belong to the provider protocol preparation, not new public
tuning options or proven conversational latency. A short sample plus two seconds
of streamed silence exercises the explicit threshold; it still does not establish
long-input turn identity or speech onset. Two request/acknowledgement checks fail
before the change; the resulting offline lane passes ten checks.

If native VAD supplies valid turn ends but no activity-start signal, evaluate
only the missing activity responsibility. Preserve provider endpoint provenance;
do not automatically replace valid native endpointing with local turn ownership.
Any composition still needs an explicit descriptor/consumer review and focused
failing tests before implementation. No detector dependency or contract amendment
is selected by this proposal.

Human conversational STT does not require the optional finite-input operation.
Its drain proof remains a separate gate only if the provider advertises
`finite_input?: true` for agent-output recognition. Do not make optional output
recognition finalization a prerequisite for the requested caller STT integration.

## Why a boundary owner is necessary

Scribe v2 realtime reports replaceable partials and committed transcript segments.
Its [commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
also permits automatic buffered commits in manual mode. The
[wire schema](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
does not identify speech-start or distinguish the cause of a commit. A segment
therefore cannot establish room barge-in or definitive input turn completion.

The [existing STT contract](speech-provider-contract.md#stt) requires genuine
speech-start and endpoint evidence. The current descriptor validator accepts
provider endpointing only. Scribe is not registered as conversational STT, and
the passing selected live protocol test does not satisfy that admission rule.

## Fallback composition if native evidence is insufficient

Use a genuine local voice detector to own acoustic activity and silence-based
endpoints, while Scribe owns recognition. Report endpoint provenance as
`external` relative to the recognition provider. This establishes acoustic gap
endpointing, not semantic understanding of whether a speaker completed a thought.
An explicit descriptor/contract amendment must admit this composition only after
its evidence and lifecycle are verified; existing provider modes retain their
current semantics.

1. A supervised allocation owns its detector state, aligned PCM remainder,
   bounded pre-roll, transcript assembly and recognition contexts. It consumes
   negotiated 16 kHz mono PCM in order. No recurrent detector state crosses
   participant, allocation or privacy-interval boundaries.
2. Voiced classifier observations establish speech-start. Silence observations
   accumulated by audio duration establish an endpoint. Missing input, a network
   timer, a transcript partial or a provider commit does not establish silence.
   Reviewed hysteresis and duration thresholds must be fixed and tested before
   exposing public tuning controls.
3. Each local turn has its own recognition assembly. A serialized manual context
   can be reused after a verified commit barrier; separate sockets remain an
   alternative when overlapping drains require independent contexts. Partial
   text and committed segments remain scoped to their turn. Automatic commits
   never emit turn-end. A fresh turn cannot receive stale text from an older one.
4. At the detector endpoint, stop audio delivery to that context and request its
   final segment. Emit turn-end only after transcript completion for the closed
   input boundary. Scribe has no commit correlation ID: determine a reliable
   finalization protocol from documented behavior and wire evidence before
   implementation claims. A raced automatic commit is insufficient proof.
5. A subsequent turn may need a separate context while the previous one drains.
   Bound concurrent contexts and retained PCM explicitly. Readiness includes the
   detector and prepared recognition connection. Connection delays, overflow,
   transcript deadlines and classifier failures fail the allocation safely;
   they do not invent completion.
6. Cancellation or permission loss retires every context and discards buffered
   text/audio. Explicit finite-input completion, if supported, waits for all
   accepted contexts and emits one ordered `input_finished`. Ordinary socket
   close, a successful commit call or detector silence does not prove this drain.
7. Usage counts project-owned accepted audio with the configured provider/model
   identity. Provider session IDs remain provider metadata. Measure any pre-roll
   or duplicated audio sent to multiple contexts separately; do not claim an
   unobserved provider billing total.

## Detector candidate and feasibility

[Silero VAD](https://github.com/snakers4/silero-vad) is selected for the local
activity runtime. Its upstream
[ONNX wrapper](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py)
uses 512 new samples plus 64 samples of context at 16 kHz and retains recurrent
state per stream. Its [license](https://github.com/snakers4/silero-vad/blob/master/LICENSE)
is MIT. [Ortex](https://github.com/elixir-nx/ortex) provides Elixir ONNX Runtime
bindings and requires Rust compilation. The pinned model and bindings now have
packaged local-runtime implementation with allocation-owned inference and a
shared public resource cache. Twenty-three focused checks pass. This does not
connect detector observations to Scribe or admit conversational STT. See
[runtime ownership and evidence](speech-activity-feasibility.md#allocation-owned-runtime-checkpoint).

Pinned identity, packaging, deterministic inference, private state and failure
supervision have focused evidence. Remaining deployment acceptance must cover
supported platforms, realistic speech/noise and CPU/backlog with the intended
number of simultaneous calls. The bounded controls do not replace those checks.
No runtime model download or additional provider credential is part of the
proposed contract.

### Feasibility review, 2026-09-30

The read-only investigation leaves both gates open. SDK documentation supports
ordinary segment buffer clearing, but does not establish which received segment
acknowledges the final manual commit under an automatic race, or how completion
is acknowledged when no buffered audio remains. The pinned official
[Python SDK](https://github.com/elevenlabs/elevenlabs-python/blob/963b4a59bc0d22f652daf426e02c048a61772a78/src/elevenlabs/realtime/connection.py#L192)
and [JavaScript SDK](https://github.com/elevenlabs/elevenlabs-js/blob/b6deef08ed7c65134176482af69ceb4d348e1817/src/wrapper/realtime/connection.ts#L648)
send an empty-audio commit without waiting for a correlated acknowledgement.

Recognized-word timestamps describe recognition output. **Inference:** measuring
their origin cannot establish a processed-through input boundary, because silent,
unrecognized or empty audio need not produce a boundary-reaching word. The
[realtime schema](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
also requires processed silent audio for keepalive messages; continuing silence
moves the accepted input boundary. SDK close terminates transcription. Neither
keepalive nor delivery observed after close establishes finite-input drain.

The [event guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
explicitly says the public API does not emit a separate `final_transcript` event,
while the pinned JavaScript SDK defines and dispatches those variants. SDK support
alone does not prove server emission or turn/drain semantics. The native-VAD
assessment must use the documented public events; it does not depend on resolving
unused SDK variants.

An optional race experiment can measure behavior or find counterexamples. It
must include input below, near and above the documented automatic boundary,
identifiable trailing speech, an automatic commit followed by a manual commit
with no new audio, and input shorter than the documented processing threshold.
Capture ordered accepted sample counts and messages. Intermediate commits and
an initial connection delay can clarify timestamp origins, but cannot prove
finalization. Prefer contract evidence before a paid matrix; no such matrix
has run. The existing selected transcription-only case remains passing evidence
for its original scope.

For the detector, pinned
[Silero v6.2.3](https://github.com/snakers4/silero-vad/blob/v6.2.3/src/silero_vad/utils_vad.py)
starts streaming activity on the first above-threshold frame. It provides
hysteresis and a minimum silence duration, but no minimum speech duration for
streaming start confirmation. Any confirmation rule must be specified and tested
by Vxpipe. At 16 kHz each 512-new-sample step represents 32 ms; the 64 retained
context samples must not be counted twice.

[Ortex 0.1.10](https://github.com/elixir-nx/ortex/tree/v0.1.10) resolves native
Rustler 0.29.1 and `ort`/`ort-sys` 2.0.0-rc.8. Its separate Elixir Rustler
requirement permits the umbrella's 0.37.3; native compatibility is untested.
The selected [ort version](https://docs.rs/crate/ort/2.0.0-rc.8/source/Cargo.toml)
requires Rust 1.70 or later; its
[build script](https://docs.rs/crate/ort-sys/2.0.0-rc.8/source/build.rs)
uses ONNX Runtime 1.19.2, with binary download/copy defaults at build time.
Silero's Python wrapper limits native thread counts; Ortex's session builder
does not set those limits.
**Inference:** per-allocation sessions may multiply native thread pools.

Before detector selection, run an isolated offline probe: pin model revision,
opset, checksum and notices; inspect ordered model shapes/types; compare
normalized PCM inference with the pinned upstream wrapper on the same fixtures;
verify arbitrary chunk splitting, independent/reset recurrent states and sample
accounting; decide incomplete-frame padding explicitly; measure native threads,
CPU and backlog under bounded concurrency. No dependency, model or probe is
installed/executed by this review.

The [Speech Engine upstream protocol](https://elevenlabs.io/docs/api-reference/speech-engine/speech-engine-upstream)
is another candidate for investigation: it sends completed speech turns to a
public WebSocket server hosted by the application and accepts response text.
It requires a callback deployment/authentication design and does not establish
standalone STT admission through the existing outbound Scribe socket. No Speech
Engine resource or provider is implemented. This alternative is not selected;
hosted-agent STS is deferred outside the current STT/TTS scope.

## Runtime feasibility update — 2026-10-01

The [isolated activity-runtime experiment](speech-activity-feasibility.md) now
pins the Silero model/checksum/license, matches the official Python wrapper,
and executes all 130 fixture frames through an unpatched native Elixir Ortex
build with zero probability difference. Independent native states for sixty-four
streams with sixteen bounded workers also match their references. Model/artifacts
remain outside project dependencies; no supervised detector is implemented.

This resolves the tested build/inference compatibility question raised by the
2026-09-30 review. Production thread/backlog limits, distribution, deployment
targets and realistic activity quality still require acceptance. Local-onset/
native-end turn correlation and long-input endpoint identity remain separate
open contracts. No shared speech admission rule changes in this research.

## Rejected shortcuts

- Treating the first partial as speech-start: recognition latency is not voice
  activity evidence, and empty/repeated partials are permitted.
- Treating every committed segment as turn-end: automatic buffered commits can
  occur during uninterrupted speech.
- Using an energy threshold as if it were a voice classifier: loud non-speech
  would become barge-in evidence without the proposed detector verification.
- Sharing one uncorrelated socket across overlapping turn finalization: segment
  events do not carry a client turn/commit identity. This would permit late text
  to enter the wrong turn.
- Weakening descriptor admission before a consumer and lifecycle exist: that
  advertises room support which the protocol preparation does not provide.

## Design review and acceptance

- [x] Prioritize native realtime VAD and separate endpoint evidence from missing onset evidence.
- [x] Keep optional agent-output drain outside the caller STT prerequisites.
- [x] Verify closed VAD protocol configuration and acknowledgement handling locally.
- [x] Run the selected short VAD case without a manual commit.
- [ ] Establish long-input endpoint identity and semantics.
- [x] Separate transcript segments from speech-start, turn-end and finite-input drain.
- [x] Identify per-allocation detector state and per-turn transcript isolation.
- [ ] If a local endpoint owner is selected, prove final-segment completion under
  automatic/manual commit races; revise the composition if the wire cannot establish it.
- [ ] If a local detector is selected, verify runtime/model feasibility and deployment ownership.
- [ ] Review the explicit conversational STT admission amendment.
- [ ] Specify readiness, overlap bounds, cancellation, privacy, usage and drain.
- [ ] Write failing tests at each owning boundary before implementation.
- [ ] Verify compiled room startup, shared conformance and persisted scoped services.
- [ ] Inspect supported capability metadata/forms in the browser.
- [ ] Pass one bounded selected conversational live case and all root/Lean gates.

The [protocol labnotes](../labnotes/20260930-1042-elevenlabs-turn-contracts.md)
record current local and live evidence. None of the unchecked gates is satisfied
by the transcription-only test. Hosted-agent STS research has separate output,
tool, history and provisioning contracts and is outside this milestone scope.
