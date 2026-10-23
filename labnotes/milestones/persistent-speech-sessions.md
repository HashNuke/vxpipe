# Persistent speech sessions

Status: complete — 2026-10-15.

## Runnable slice and prerequisites

Call capabilities retain their realtime provider connection across utterances
and turns. Prerequisites are the completed semantic speech/provider packages,
Rime/Google speech integration, and realtime Morse synthesis. The
[decision](../../docs/persistent-speech-sessions.md),
[provider contract](../../docs/speech-provider-contract.md), and
[ownership contract](../../docs/speech-session-ownership.md) define boundaries.
The user's new requirement supersedes the earlier acceptance of per-utterance
request transports. Historical milestones remain evidence of their old scope.

## Approved contracts

- One capability-owned realtime transport; no cross-participant pooling.
- Repeated TTS utterances reuse the socket with exact completion identity.
- Cancellation fences delayed audio/control without contaminating the next turn.
- Responsive control, bounded credit, buffers, contexts and operation deadlines.
- Documented keepalive and explicit provider lifetime/disconnection handling.
- Model catalog and activation expose only compatible call transports.
- Preserve persistent STT/STS semantics and local providers.
- Google streaming HTTP TTS is an explicit user-approved exception; preserve it
  without mislabeling the request stream as a persistent synthesis session.

## Checkpoints

- [x] Inspect provider implementations and record the transport audit.
- [x] Confirm ElevenLabs/Cartesia context protocols and Google API distinction
  from primary documentation.
- [x] Red/green capability-owned TTS transport and lifecycle regression tests.
- [x] ElevenLabs persistent context WebSocket and compatible model selection.
- [x] Cartesia persistent context WebSocket.
- [x] Go Morse multi-context compatibility and persistent Vxpipe adapter.
- [x] Resolve Google TTS availability and selection without implicit fallback:
  the user retained streaming HTTP TTS as an explicit exception.
- [x] Verify repeated turns for existing persistent STT/STS paths.
- [x] Repair historical manual Scribe STT per-turn reconnection while preserving
  pinned endpointing semantics, actual PCM timeline and room transcript identities.
- [x] Pass isolated repeated-recording and distinct-recording manual STT live
  checks, plus changed TTS live checks, with no telephony.
- [x] Bound Deepgram TTS generation and cancellation when terminal evidence is
  missing on an otherwise open connection.
- [x] Verify local Morse socket interoperability and interruption/cleanup.
- [x] Independent review of teammate implementation; repair/review any findings.
- [x] Pass root format/compile/Credo/tests/dependency checks and Lean lane.
- [x] Synchronize docs, milestone evidence and user-visible catalog.
- [x] Commit/push/deploy the Go endpoint and verify its hosted protocol before
  publishing the dependent Vxpipe adapter; then commit/push that checkpoint.

## Design review, separate from implementation

Dependency order reviewed before implementation: the Go completion protocol must
exist before the Morse adapter can depend on it. Context identity belongs to
provider adapters, while playback credit and permission ownership remain in the
speech engine. Healthy transport lifetime must not depend on utterance-task
lifetime. Google compatibility cannot be solved by changing a URL or using an
unstructured conversational response as exact synthesis. Completion boxes remain
open until the corresponding behavior and checks are implemented.

Independent design review confirmed scope and index placement, then required
explicit deployment ordering, flush-plus-context-close completion, more-than-five
utterance cleanup, real PCM continuity and clear failure for unsupported pinned
Eleven v3 selections. These contracts are now recorded; this design review does
not constitute implementation or live acceptance.

## Verification evidence

- Shared TTS protocol/session/local-socket tests: 41 passed. Independent review
  accepted connection readiness, context retirement, cancellation races,
  credited large PCM frames and tagged idle keepalives.
- Existing persistent STT/STS regression selection: 147 passed.
- Focused live providers, without telephony: ElevenLabs TTS (idle, cancellation,
  six phrases), Cartesia TTS, Deepgram TTS and local/hosted Morse TTS passed.
  Hosted Morse independently decoded both utterances at all four sample rates.
- Manual Scribe live repeated/distinct recordings and forty seconds of real
  silent PCM followed by speech: 3 passed in 57.2 seconds. After the queued-turn
  wire-byte correction, all three live cases passed
  again (57.1s). The focused manual suite passed 30/0 and final independent
  review accepted the accounting and serialized idle commits.
- Go race suite and vet passed. Independent cancellation/overload probes passed.
  Go commit b81e882 is pushed; v0.1.4 binaries passed GitHub CI and are published.
  Railway deployment c3d76d67-43b9-4baa-91e0-cc5e17fb1d78 reached SUCCESS;
  public smoke, llms.txt and Vxpipe hosted interoperability passed afterward.
- Final Vxpipe format, warnings-as-errors compilation, strict Credo,
  unused-dependency and Lean checks passed. The complete umbrella run passed
  all 1,653 cases outside CallEngine. After correcting its five new STT test
  failures, the sequential final CallEngine rerun passed 2,223 cases, zero
  failures, 75 exclusions (seed 714943). Combined current default coverage:
  3,876 cases, with 131 integration/live exclusions.
- An intervening CallEngine run exposed one unchanged lifecycle test receiving
  `:noproc` before its explicit timeout. The isolated 19-case same-seed rerun
  and full sequential rerun both passed. It selects no speech provider;
  the cause of that early room exit is unproven and recorded in the labnotes.
- Implementation, focused tests, decision and this milestone ship together on
  the `morsecode-api` branch, after the Go endpoint was deployed and verified.
