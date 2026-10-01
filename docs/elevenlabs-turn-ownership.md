# ElevenLabs input turn ownership

Status: Design proposal, updated 2026-10-01. Scribe manual and short native VAD
protocol preparation are verified;
native VAD admission and the fallback boundary composition are not implemented
or admitted by the conversational STT contract. This document records unresolved
feasibility gates separately from milestone progress.

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
3. Each local turn has its own Scribe socket/context. Partial text is scoped to
   that context; committed segments accumulate within its turn. Automatic commits
   never emit turn-end. A fresh turn cannot receive stale text from an older
   context.
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

[Silero VAD](https://github.com/snakers4/silero-vad) is a candidate speech
classifier, not an approved new dependency. Its upstream
[ONNX wrapper](https://github.com/snakers4/silero-vad/blob/master/src/silero_vad/utils_vad.py)
uses 512 new samples plus 64 samples of context at 16 kHz and retains recurrent
state per stream. Its [license](https://github.com/snakers4/silero-vad/blob/master/LICENSE)
is MIT. [Ortex](https://github.com/elixir-nx/ortex) provides Elixir ONNX Runtime
bindings and requires Rust compilation. These are implementation candidates;
native build compatibility and performance have not been verified in Vxpipe.

Before selecting them, verify a pinned model revision and checksum, distribution
and license notice, supported deployment platforms, deterministic local inference,
allocation-state isolation, bounded concurrency and failure supervision. Include
speech, silence and non-speech noise fixtures. Measure CPU and backlog with the
intended number of simultaneous calls. No runtime model download or additional
provider credential is part of the proposed contract.

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
