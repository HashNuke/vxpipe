# Transcript start and optional VAD

Status: complete, 2026-10-11, under the user-clarified speech-start acceptance
criterion. `vad` defaults to false and is API-only. First nonempty transcripts
start the human turn and interrupt agent output; optional local VAD can start it
earlier. Recognition accuracy and human listening remain documented follow-ups;
see the final scope decision below.

## Runnable outcome

A published call uses the first nonempty human transcript to interrupt agent
output by default. The same call with `speech_to_text.vad: true` can interrupt
before text arrives, using local Silero. Scribe uses automatic VAD commits in
both modes. The option is available through call-spec APIs; no Console toggle is added.

## Prerequisites and sources

Implemented prerequisites:
[Simpler speech integrations](simpler-speech-integrations.md),
[Provider integration packages](provider-integration-packages.md),
[Provider expansion and live acceptance](provider-expansion-and-ai-gateway.md),
[Tenant provider configuration](tenant-provider-credentials-and-platform-configuration.md),
and [Call spec editor](call-spec-editor.md).

Design sources: [Speech-start decision](../../docs/stt-speech-start-detection.md),
[Speech provider contract](../../docs/speech-provider-contract.md),
[Speech authoring guide](../../docs/speech-integration-guide.md),
[Scoped ownership](../../docs/speech-session-ownership.md),
[Current Scribe implementation](../../docs/elevenlabs-stt-session.md),
[Inline provider selections](../../docs/inline-provider-selections.md),
and [latency evidence](../20261011-0333-scribe-partial-latency.md).

This slice does not depend on unfinished STS provider acceptance, AI gateway
routing, packaging, or retention, and does not release their existing holds.

## Contracts

- Add one optional boolean `vad` to the portable human `speech_to_text` selection.
  Omitted and false mean transcript start; true enables Silero onset plus
  transcript fallback. Validate its type/path and reject it on other capabilities.
  Never send this setting to provider APIs. It participates in compiled identity,
  readiness signature and publication consistency.
- Preserve whole-selection inheritance: defaults apply when the capability is
  inherited; a participant override replaces the selection, with omitted `vad`
  meaning false. Switching provider/model retains the explicit common setting.
- Support every currently registered human STT model: Deepgram Flux, Google live
  transcription, Cartesia, ElevenLabs Scribe and local Morse. Silero does not
  reliably recognize Morse tones; transcript fallback preserves that provider.
  Future STT registrations must pass the same common composition contract.
- Turn start and turn end are separate authorities. Provider-specific semantic,
  gap, eager and resume behavior stays intact. VAD silence does not end a turn or
  commit provider text. Provider-native starts establish correlation internally;
  they cannot bypass transcript start when VAD is off.
- Nonempty means trimmed text has content, not a confidence or minimum-word
  threshold. Publish start before its first transcript with one canonical turn
  reference. Final-only text gets start/text/end in order. Ignore empty initial
  partials and repeated keepalives; revisions retain the turn. A changed partial
  is not a new turn. Provider-end boundaries close correlation explicitly.
- In VAD mode, associate detector onset and recognition with the same admitted
  audio interval. One early VAD start plus later text produces one interruption.
  Repeated acoustic starts inside an open provider turn do not produce duplicate
  starts; semantic resumes retain their reference. Preserve eager/resume paths
  without manufacturing an eager endpoint from local silence.
- A VAD-started turn with empty final recognition may settle with no model request.
  If recognition never supplies its required boundary, apply bounded existing
  session failure/timeout handling; do not invent text or silently change modes.
- No per-call Silero preparation, detector workers or inference with VAD off.
  With it on, scoped readiness requires the detector and recognizer. Failures
  fail the allocation through its owning supervision path. The immutable lazy
  model cache can remain shared; recurrent state and audio remain private.
- Preserve input credit, provider queue limits, cancellation, adoption and caller
  usage accounting. Both detector and recognizer see identical admitted PCM;
  no acoustic gating, duplicate PCM billing or unbounded fork queues.
- Silero needs 16 kHz mono S16LE PCM. Normalize only its branch using the owning
  decode path and existing engine PCM resampling; preserve the recognizer's
  declared encoding/rate. Deepgram currently recommends 48 kHz and also permits
  Opus, so enabling VAD cannot assume recognition input is already 16 kHz PCM.
  Decoder state, resampler history and sample-clock mapping must stay scoped to
  the same admission/generation. No Call Engine dependency on Gateway internals.
- Acknowledged source identity, allocation generation, connection incarnation,
  policy revision and input/output permission intervals remain required. Hold,
  denial, replacement, transfer or owner loss retires detector and recognition
  state. Old partials, finals and inference completions cannot interrupt or
  publish into a new interval. Provider sequence is not reused as VAD sequence.
- Scribe's conversational default becomes `commit_strategy: vad`, with one owned
  continuous recognition stream per permission allocation. Fresh allocations
  lose old context. Local VAD changes onset only. Raw manual helpers remain for
  protocol experiments, not as an implicit conversational fallback.
- Automatic Scribe segments must preserve cumulative text and real conversational
  endpoints. Establish how long-input forced commits are distinguished from VAD
  commits before declaring all committed text a `provider_gap` turn end. If the
  wire protocol cannot support that distinction, record the evidence and resolve
  a truthful bounded endpoint contract before the default switch ships.
- Already-running calls and immutable publications are not rewritten. Audit
  persistence of old compiled settings/identities; old pinned snapshots must
  either retain their behavior or fail with an explicit migration path. New
  publications/preparations resolve the new default. Do not silently rehash old
  revisions or broaden their provider permissions.
- Human input STT changes only. Agent output transcription and native STS
  controllers retain their current ownership, finite-input and evidence contracts.

## Architecture

Compose recognition and onset once inside the allocation-owned speech lifecycle,
using an internal conversational STT coordinator rather than duplicating Silero
in each adapter or adding unrelated work to RoomAuthority. The selected registered
provider and its usage identity remain visible; public configuration cannot select
an arbitrary wrapper/module.

The coordinator is the sole producer on its outer semantic channel. Its inner
recognizer has an owned scoped session and acknowledged events. Optional activity
inference uses the existing ActivitySupervisor/ActivityRuntime/Silero boundary.
Both sources enter an ordered, bounded coordinator with explicit source tokens;
only canonical events cross the outer channel. Inner readiness, finite-input
support where applicable, usage and teardown need conformance proof. This avoids
injecting a second producer directly into Speech.Channel or bypassing Session.ack.

Adapter-native turn references remain correlation keys. The coordinator maps them
and an optional early acoustic turn to one canonical reference. Serial provider
segments cannot be matched using transcript text equality alone. Complete explicit
rules for provider segmentation/resumption and queued turn settlement in checkpoint
A before implementation. Update Descriptor so recognition capability and configured
speech-start evidence remain truthful, without changing STS evidence admission.

## Checkpoint A — Contracts and compatibility

- [x] Write focused failing tests for `vad` parsing/defaults, inheritance,
  provider switching, identity and old publication/compiled-plan compatibility.
- [x] Inventory provider onset, interim/final and endpoint events; define native
  reference mapping for each adapter and confirm no input/output-STT coupling.
- [x] Probe Scribe automatic VAD and forced long-input commits; record exact
  metadata, whether boundary reasons can be distinguished, and the endpoint
  decision. This is a blocking design gate, not a promised API capability.
- [x] Define the permitted PCM fork for 16/48 kHz, Opus/native WebRTC, telephony
  and configured Morse formats. Locate decoder ownership and prove the VAD
  branch can receive normalized audio without changing upstream selections.
- [x] Finalize descriptor evidence, bounded orphan-acoustic-turn handling,
  no-word completion, eager/resume correlation and current resource limits.
- [x] Implement only the approved schema/compilation contracts after red tests;
  new behavior stays unadvertised until a runnable provider slice passes.

## Checkpoint B — Shared onset composition

- [x] Write failing coordinator tests for empty/repeated/revised partials,
  final-only results and start/text/end order with VAD off.
- [x] Write failing tests for VAD-before-text, text-before-VAD, missed VAD,
  multiple detector starts within one provider turn, empty final and semantic resume.
- [x] Implement scoped composition, canonical references and ordered delivery;
  preserve acknowledgment and provider identity across inner/outer allocations.
- [x] Prove VAD-off startup/inference does not require Silero; VAD-on preparation,
  owner loss, bounded input, failure propagation and cleanup have focused evidence.
- [x] Prove prepared adoption, hold/reopen, denied audio/transcripts and stale
  inference/provider events cannot acquire new permission provenance.
- [x] Prove 48 kHz and Opus selection handling, resampler/decoder reset across
  cutover, matched sample timing and no duplicated input credit/usage.

## Checkpoint C — Providers and room interruption

- [x] Migrate Scribe to the checkpoint-A endpoint decision and VAD commit default;
  remove its unconditional local detector/manual-turn dependency for new calls.
- [x] Adapt Deepgram, Google, Cartesia and Morse to the common onset choice;
  preserve their endpoint, eager/resume, cumulative and final-text semantics.
- [x] Prove normal room agent-output interruption/replacement in both modes;
  correlate late final text with the correct caller turn and permission interval.
- [x] Pass automated two-turn, short-answer, long-turn, quiet/synthetic-noise,
  no-word and detector-failure scenarios without empty model requests or duplicate
  interruption. The appended-answer accuracy case is a documented follow-up.
- [x] Retain existing output-STT finite-input/drain, private briefing, native STS
  and usage/privacy integration checks; no provider is disabled to make tests pass.

## Checkpoint D — API integration and documentation

- [x] Prove the API accepts explicit true/false and defaults omitted `vad` to false;
  validate field errors through tenant save/publish/prepare operations.
- [x] Preserve the setting through source/visual round-trip and provider/model
  changes without adding a Console control. Verify save/publish digest consistency.
- [x] If frontend source preservation needs a change, inspect its rendered source
  editing/save flow; no new setting UI or toggle is in scope.
- [x] Update call-spec source/editor guides, speech contract/authoring guide and
  ElevenLabs session docs to describe implemented behavior and real provenance.
- [x] Keep the latency measurement skipped unless explicitly opted in; do not
  make provider timing assertions part of ordinary acceptance.

## Checkpoint E — Acceptance

- [x] Run focused project-owned tests for each checkpoint using red-green-refactor.
- [x] Run root format, warnings-as-errors compile, strict Credo, default tests and
  unused-dependency check; fix project-owned failures before marking completion.
- [x] Run bin/verify-lean for changed speech/source-cutover transitions and record
  modeled contract changes or actual coverage limits.
- [x] Run explicitly tagged live Scribe short/repeated/long-input cases in both
  onset modes through bin/livetests; record provider/model, settings and limitations.
- [x] Verify web voice interruption during actual agent playout, retained caller
  text and the next reply through automated WebRTC/RTVI checks in both modes.
  Human listening is an unperformed follow-up under the clarified acceptance scope.
  Hosted checks cover distinct short answers and extended input across segments.
- [x] Verify restart and old-publication preparation, then record final evidence
  and synchronize this checklist/index. Leave the milestone open on unresolved gates.

## Specification review — separate from implementation

Reviewed against current source and the user request on 2026-10-11. The common
setting is separated from upstream options; default transcript authority applies
also to adapters with native onset events. Endpoints, output-STT and STS retain
separate responsibilities. All direct prerequisites are already implemented.

Review identified four required contract checks: Scribe forced-commit versus
silence endpoint evidence, old pinned snapshot compatibility, correlation of
an early acoustic start with provider segments/resumes, and normalized VAD PCM
for recognizers using 48 kHz or Opus input. These remain checkpoint-A
implementation gates. The measured latency supports the user-selected tradeoff,
not a provider-independent latency promise. This specification review predates implementation; the checkpoint checklists above now track actual evidence.


## Authorized checkpoint sequence — 2026-10-11

Execute A → B → C → D → E. Start each behavior change with the smallest
project-owned failing test and record red/green evidence in the implementation
labnote. Checkpoint A resolves the provider endpoint and compatibility evidence
before B creates shared composition; C connects it to supported providers and
real room interruption; D proves API-only authoring and updates documentation;
E runs final local, model, hosted and listening acceptance. Partial work never
checks off milestone acceptance. The default is explicitly `vad: false`.

## Implementation evidence — 2026-10-11

Common boolean authoring defaults to false, remains outside upstream options and
is preserved by source edits without a Console control. Historical compiled
selections missing the field retain native/manual behavior and their hashes.
New false/omitted selections retain historical identity hashes; true changes them.
Tenant save/publish/fetch and codec checks pass. Full prepare/error-path coverage
for both modes remains open where not directly demonstrated.

The sole outer producer owns an acknowledged inner recognizer and optional
Silero runtime. Coordinator tests pass47 cases after teammate fixes and both
independent reviews. Wrapper tests pass9 cases plus an independent retired-final
regression; combined PCM/wrapper/continuous checks pass18 cases. Google capacity
is preserved with9 tracked turns (8 pending finals and1 active); other native bounds
are unchanged. Prepared/stale provenance, detector reset, retained empty-final
text and timeout protections have focused red/green evidence. Existing room
hold/privacy/output-STT/STS regressions pass in the full Call Engine run.

Scribe uses automatic commits and explicitly inferred_gap endpointing: after a
commit,1.5 seconds without changed nonempty text and without an outstanding draft
settles committed cumulative recognition. New drafts await their commit or timeout. Wire events lack commit-reason metadata; the
forced commit probe observed36 seconds during continuous input. This inference can
split continued speech when recognition stops revising, and local VAD changes
onset only. The60-second draft commit watchdog and canonical inactivity deadline
fail the allocation rather than manufacture text.

Earlier four tagged hosted wrapper cases passed in both modes (seed 414887), but
the long successes used draft settlement later rejected by review. A repeated
uncommitted partial reopened a phantom turn. The corrected path waits for the
draft commit; long-input acceptance remains unresolved.
The configured published-room case remains failing: the provider never emits the
brief appended 'yes' word in its partial/committed recognition for the repeated
long corpus. Keep that acceptance gate open; do not substitute wrapper success
for published-room evidence or weaken the known-word assertion.

Frontend562 tests, TypeScript and lint pass. Rendered Chrome source Apply, provider
switch, JSON round-trip and draft save preserve vad=true at desktop/mobile sizes
without a toggle. Lean build/oracle/source-gate replay passes; this existing lane
does not model the new coordinator or Scribe inference heuristic. Strict Credo
passes after moving audio delivery into existing EventDelivery. The final root
run passes; the web voice listening check remains pending. No commit was requested.

Detailed red/green runs, failed experiments and verification limits live in
[implementation labnotes](../20261011-0510-implement-transcript-start.md).

Current corrected hosted rerun: both selected long-input cases fail to settle
with local VAD false/true (seed 456239). This gate remains open; the inferred
endpoint cannot be accepted on the earlier superseded passing evidence.

Final local verification passes: root format, warnings-as-errors compile, strict
Credo, unused dependencies and the complete default umbrella suite (seed 913907).
The final Lean source-gate oracle/replay lane passes (seed 996288), with the coverage
limit stated above. Mechanical keyword-list hygiene in the new coordinator/runtime
tests subsequently passes49 focused tests (seed 458330); runtime behavior is unchanged.
The milestone index remains unchecked because Scribe endpoint/hosted and manual
acceptance are unresolved. No commit or push was requested.

## Bounded Scribe draft flush — 2026-10-11

The hosted protocol probe confirms an explicit commit is supported while the
connection retains VAD strategy. The adapter now requests one commit after a
post-commit draft stops revising for 1.5 seconds, then requires nonempty committed
text within five seconds. Blank responses retain the draft and deadline. No local
acoustic inference is introduced; endpoint evidence remains inferred_gap.

Four ordinary hosted cases passed: distinct turns and 45-second input, each with
local VAD false and true (seed 513957). This supersedes the earlier unresolved
long-input result, without accepting configured-room or listening gates. Focused
empty-response review regression passes 12 tests (seed 575753). Root and Lean
checks are reopened for this runtime change. See the
[draft-flush evidence](../20261011-0639-scribe-vad-flush.md).

Final sequential verification after the reviewed flush fix passes: format,
warnings-as-errors compilation, strict Credo, unused dependencies, Lean
build/oracle/replay (seed 554342), and every default umbrella suite (seed 303467).
The Lean lane retains its source-gate coverage limit; it does not prove Scribe's
inferred endpoint. Documentation links and whitespace checks pass. Configured-room,
manual listening and the remaining unchecked integration gates keep this milestone
open. No commit or push was requested.

## Room onset and API preparation proof — 2026-10-11

A new room integration test sends the public PCM fixture through normal ingress
with local VAD enabled while Google-backed agent playout is active. Acoustic onset
interrupts before any provider transcript, then partial/final text retains that
caller reference and produces the next reply without another interruption. Together
with the transcript-default room test, onset-to-playout integration is proven in
both modes. This does not close the whole replacement/late-final gate by itself.

Tenant API tests cover omitted, false and true through save, immutable publication,
compilation and PlanStartup preparation with platform and tenant credentials.
Omitted prepares false; explicit fields survive publication. Invalid boolean values
fail with the precise source path before publication. Checkpoint D's API gate is
complete. Existing field-error compilation tests and persistence tests retain their
coverage. Focused room and Console suites pass (seed 721116); root format,
compilation, Credo and unused-dependency checks also pass. No runtime code changed
after the preceding full-root and Lean verification.

The PCM cutover audit found STT Opus normalization resources persisted across the
receiver hold/arm barrier. Focused red tests preceded a reset after successful hold:
new decoder and encoder retain the format/ingress, and reset failure cannot produce
an armable receipt. Cutover/SpeechInput checks pass 17 tests (seed 668014). Root/Lean
checks reopen for this source-cutover fix; the composite PCM/usage gate remains open
until its complete evidence is assembled.

The composite PCM/usage gate is now verified by allocation wrapper 48 kHz/Opus
forwarding, STTActivityPCM absolute timestamp/sidecar validation, ingress combined
byte-credit bounds, source hold normalization reset, stale detector-completion
retirement, and new outer capability usage checks in both onset modes. The latter
passes two tests (seed 780038): each raw recognition payload is forwarded once,
there is one outer attempt, and the final provider audio/text deltas are emitted
once with no inner observations. Its initial setup run omitted installing the
policy and therefore correctly suppressed text measurement; applying the policy
through Enforcer corrects the fixture. This is coverage of existing runtime
behavior, not a new billing policy or proof of hosted provider billing precision.

Room interruption/next-reply checks in both onset modes are now complemented by
outer capability permission replacement checks in both modes (four usage/lifecycle
tests pass, seed 72024). Denial retires the recognizer and cancels its usage attempt;
reopening creates a new allocation and attempt. A deliberately late event from the
old inner allocation is ignored even when its native turn reference is reused by
the new recognizer. Final text belongs to the new policy interval and usage attempt.
Provider turn indexes restart per allocation, so tests assert policy revision and
generation rather than invent a globally increasing index requirement. This closes
the combined interruption/replacement gate. No runtime code changed for this proof.

The expanded tagged ordinary Scribe lane passes all four cases (seed 397253,
152.9 seconds) against the reviewed current adapter: 45-second input in each
onset mode, plus phrase/brief-answer/repeated-identical-answer turns in each mode.
Three seconds of admitted quiet PCM after every short-turn settlement emits no
semantic events. Provider/model: ElevenLabs scribe_v2_realtime, language en,
commit_strategy vad, local VAD false/true. This closes the explicit ordinary live
gate, while configured-room corpus recognition and listening remain unresolved.

Final source-cutover verification passes sequentially: format, warnings-as-errors
compilation, strict Credo, unused dependencies, Lean build/oracle/replay (seed
550001), and the full default umbrella suite (seed 791499). The added outer usage/
lifecycle cases ran separately after the root Call Engine lane had loaded its test
files; all four pass (seed 72024), with final format/Credo checks passing as well.
The existing Lean source-gate coverage limit remains explicit. Global acceptance
is still incomplete: configured-room corpus recognition, quiet/noisy web voice listening
and restart/publication preparation remain open.
No commit or push was requested.

Fresh-VM restart/publication preparation passes in two independent VMs against
persisted/reloaded published snapshots. Stored bytes and identities stay unchanged;
actual STT readiness/retirement verifies current omitted/false/true and historical
manual Scribe behavior. The explicitly tagged integration lane passes (seed 204280),
with root format/compile/Credo/unused dependencies and outer usage/lifecycle checks
green. See the [restart test](../../apps/vxpipe_console/test/integration/stt_restart_compatibility_test.exs)
and [implementation evidence](../20261011-0510-implement-transcript-start.md).
Remaining gates are configured-room corpus recognition and quiet/noisy web voice
listening. The milestone index remains unchecked.

The configured-room diagnostic verifies exact outbound fixture PCM through the
socket API: all 774,400 bytes, in order, one connection (seed 906572). Provider
partials/commits still omit the appended brief answer, so the existing word-fidelity
assertion fails. This supports a hosted recognition limitation while retaining the
lack of server-side per-chunk acknowledgement. See [outbound evidence](../20261011-0737-scribe-room-audio.md).
The configured-room and quiet/noisy listening gates stay open. A web voice listening
pass still needs a listener to speak over agent output.

## Verification scope correction — 2026-10-11

The user clarified that telephony is unnecessary for this speech change. The
selected Telnyx self-call was an extra check added during implementation; it is
removed from acceptance. Its failed public Funnel DNS readiness check occurred
before dialing and does not block this milestone. Streamed-audio tests and web
voice checks cover the required speech behavior without a telephony carrier.
Configured-room ASR fidelity and quiet/noisy web voice listening remain open.

## Resumed noise and WebRTC verification — 2026-10-11

Two hosted cases pass with local VAD false and true (seed 625027): reproducible
low-level broadband noise alone emits no turn, and the public speech fixture mixed
with that noise retains its expected word in one canonical turn. Quiet/noise after
settlement emits no events. This is bounded synthetic-noise coverage, not a human
microphone listening result.

The WebRTC/RTVI test now covers both onset modes through actual peer connections
and Opus RTP. Blank native onset emits no client event; the first nonempty partial
interrupts active agent output, retains final caller text and produces the next
reply. Both variants and the neighboring web contracts pass (seed 635784), including
actual agent audio playout before the interruption. An initial run exceeded the inherited 100 ms TTS startup
assertion; that acknowledgement now has a bounded five-second timeout. No runtime
behavior changed for these acceptance additions.

A 300 ms intra-utterance pause did not resolve the configured-room missing-answer
case (seed 901442); exact outbound audio remained intact. The original fixture and
fidelity assertion are retained. Acceptance remains pending that recognition gate
and the human web voice listening pass; scope questions are awaiting an answer.

Final resumed root checks pass: format, warnings-as-errors compilation, strict
Credo, unused dependencies, the full default umbrella suite (seed 673225) and Lean
verification (seed 569839; source-gate coverage limit unchanged). Frontend tests,
TypeScript and lint pass. No telephony acceptance is required. The configured-room
missing-answer case and human web voice listening remain unchecked pending their
actual verification or an explicit scope decision.

## Follow-up record (not milestone gates)

The [Scribe appended-answer issue](../issues/scribe-appended-short-answer.md)
contains the reproduction, observed evidence and limits. The final scope decision
below defers this accuracy case while preserving the existing live assertion.

The outstanding human web voice pass should record provider/model, onset mode,
microphone conditions and the observed interruption/text/reply sequence:

- [ ] With `vad: false`, speak over audible agent output; verify one interruption,
  retained caller text and a subsequent reply.
- [ ] Repeat with `vad: true` using the same provider and source configuration.
- [ ] Exercise distinct brief answers and an extended utterance spanning provider
  segments, first in quiet conditions and then with ordinary background noise.
- [ ] Record perceived responsiveness and any missing words or duplicate turns.

Automated WebRTC and synthetic-noise results above support these scenarios. No
human listening result has been recorded. These unchecked follow-ups are retained
for later listening work; they are not claimed as passed.

## Final acceptance scope — 2026-10-11

The user accepted the missing final word as tolerable for this milestone and
clarified the criterion: the first partial must arrive and serve as the speaker
start event. We apply that criterion to the existing automated speech-start and
web interruption evidence. Human listening remains a follow-up rather than a
requirement to close this implementation milestone; no listening quality is claimed.

The first nonempty transcript emits one canonical start before text. Revised
partials remain on that turn, and final text settles it. This ordering is verified
by the coordinator/allocation tests and WebRTC interruption during actual playout
(seed 635784). Hosted Scribe short/repeated/long and synthetic-noise cases verify
live onset in both modes. API preparation, compatibility, ownership, privacy and
usage checks remain required and passed; the scope decision does not waive them.

The configured-room accuracy test still fails because the appended “yes” was absent
from all observed provider partials and commits. A later partial could generally
revise text, but that did not happen in this fixture. The issue and unchanged tagged
live test remain available; the acceptance decision does not claim a recognition
fix or guarantee every word will eventually appear.

Final evidence remains the default umbrella pass (seed 673225), root format,
warnings-as-errors compilation, strict Credo, unused dependencies, Lean verification
(seed 569839, existing source-gate coverage), frontend tests/TypeScript/lint,
restart/local-room/usage integration (seed 903047), WebRTC playout (seed 635784), and
hosted noise cases (seed 625027), together with earlier hosted repeated/long cases.
Only documentation changed after those runs. Telephony is outside this milestone.
