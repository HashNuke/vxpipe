# Implement transcript start

## Authorized scope

Implement the transcript-start/optional-VAD milestone in checkpoints A through E.
The common input-STT `vad` field defaults to false and is API-only. No Console
control, output-STT change, commit or push is authorized for this checkpoint.

## Contract and schema evidence

- The initial focused schema tests failed because `vad` was rejected and the
  compatibility accessor was missing (3 tests, 2 expected failures).
- The parser now accepts a boolean only for human STT, defaults to false and
  rejects the field on other capabilities. Upstream provider options exclude it.
- Omitted/false preserve historical selection identity; true changes identity.
  Old decoded structs missing the new field validate and read as false.
- Focused selection tests plus existing inline-selection tests passed (6 tests).
  Inheritance, publication/runtime compatibility and API workflow checks remain.

## Scribe endpoint evidence

The existing explicitly tagged long-VAD integration test passed through
`bin/livetests run`: a committed segment arrived during continuous speech at
36,000 ms of accepted PCM; another arrived during trailing silence at 42,740 ms.
The first segment proves that automatic commits cannot all be treated as human
turn endpoints. This remains a blocking endpoint-design gate. No live credential
file was inspected. The public event reference supplies stable segment text;
it does not document a commit-reason discriminator.

## Shared composition work

A narrow `bin/teammate` task in tmux session `vxpag` produced the pure coordinator
and its tests. Both independent read-only reviewers found bugs despite 27 passing
tests: empty-final starts, queued-text loss, native-hint/VAD miscorrelation,
unbounded control buffering, revisions after final and stale references after
reclamation. A second teammate run in the same session is fixing these with
regression tests. This work is not accepted until rereview passes.

Initial wrapper tests failed (4 failures) before the wrapper existed. The scoped
wrapper is being implemented separately and is not yet connected to published
calls. It owns an inner acknowledged recognizer, emits through the sole outer
producer, and optionally prepares an allocation-owned activity runtime. VAD-off
startup does not create activity workers. Format normalization and generation
fencing acceptance are still pending.

## Shared composition accepted and integrated

The teammate coordinator needed three review/fix rounds. Final independent reviews
accepted 46 focused tests after canonical empty-final text retention was corrected.
The shared allocation wrapper now acknowledges an inner owned session, supplies
canonical references and uses no detector when vad=false. Optional Silero observes
accepted PCM without gating recognition. Prepared references are tombstoned so
pre-adoption text cannot acquire authority later. Native/48k PCM and decoded Opus
are normalized only for the detector; input credit includes decoded sidecar bytes.
Supported recognizer rates include 32k/44.1k with pre-expansion bounds.

Wrapper review reproduced stale detector queues, stale-final epoch changes and
interim text removing endpoint deadlines. Focused red tests preceded the fixes.
Canonical settlement resets old detector state/queued input; old in-flight results
cannot mutate the new boundary. Active interim recognition retains a 60-second
inactivity deadline. Independent rereview passed nine wrapper tests and an external
retired-final regression. Combined wrapper/PCM/continuous tests passed 18 tests.
The registered Scribe close callback was separately red then green. Google supports
eight pending finals plus one active turn; teammate is correcting the common bound
from four to nine with a focused regression and independent rereview.

## Scribe endpoint decision and hosted evidence

Automatic wire events expose only message_type/text, without a commit reason.
The continuous adapter accumulates commits and declares inferred_gap: 1.5 seconds
without changed nonempty text after a commit settles retained text, including a
possible draft tail. Repeated/blank keepalives do not extend the candidate. This
can split continued speech if recognition does not revise, and is not acoustic or
provider-semantic evidence. A draft's missing commit has a 60-second watchdog.
Initial partial-only timeout failed red, then passed after implementation.

First two hosted wrapper runs passed short/distinct turns but failed long settlement:
a new partial after the trailing-silence commit removed the endpoint candidate.
A focused retained-draft test failed red; rescheduling the inferred candidate on
changed draft revisions fixed it. The third hosted run passed all four cases in
121.5 seconds, seed 414887: short/repeated distinct turns and 45.04-second continuous
input spanning forced commits, with local VAD both off and on. No credential env
was read; bin/livetests loaded credentials only in its child process.

The configured published-room live case currently fails its final public 'Yes'
word assertion. It is under investigation; passing wrapper cases do not replace
this room evidence. A subsequent run uses 20ms PCM and continued silence while
draining. The original default root run had old onset/manual fixtures failing;
those were migrated while retaining explicit legacy manual coverage. The second
root run is still underway and has an MCP handshake test timeout under concurrent
verification load. Root success is not claimed.

## API and Console evidence

Tenant persistence tests pass save/publish/fetch with explicit false/true and
invalid value paths; pinned codec tests preserve old/new identities and settings.
The invalid-save fixture originally exhausted its fixed ID generator; reusing the
saved spec ID corrected the test (8 tests pass). Console credential inheritance
checks now assert the actual wrapper and inner provider configuration, rather than
expecting a direct native provider (3 local configured tests pass, 1 live excluded).

Frontend source/field validation red run failed four cases, followed by passing
focused checks. The full frontend suite passes 562 tests across 71 files; TypeScript
and lint pass. Chrome Storybook inspection at desktop and 390x844 verified API VAD
true preserved through source Apply, Google provider switch, JSON round-trip and
Save as draft (revision4), with no VAD control. Storybook uses mock persistence;
backend database save/publish evidence is separate.

Lean lane passes existing source-gate oracle build/drift/replay (one replay test).
It does not model the new transcript coordinator or Scribe inferred-gap heuristic.
Strict Credo flagged Channel exceeding800 lines after the new provider readiness
query. Audio dispatch moved mechanically into existing EventDelivery, its cohesive
owner; existing session suites are running. Final root checks remain pending.

## Capacity and configured live follow-up

The Google capacity amendment passed red/green (47 tests, one initial failure),
then both required independent reviewers accepted 47 tests without failures.
The common coordinator now permits nine tracked turns while per-provider queue
bounds remain unchanged; a tenth unmatched reference still fails safely.

The configured live retries at 20ms pacing and continued quiet still failed the
appended short-word assertion (the second and third configured live runs). Opt-in wire summaries contain no transcript text:
only event type, byte count, keys, duplicate/commit comparison and matches for the
public fixture's 'telescope'/'yes' words. The provider's partials and committed text
never contained 'yes'; cumulative adapter assembly therefore cannot retain that
word. This remains unresolved hosted recognition acceptance, not repaired by
weakening the assertion or inventing text. The four separate hosted wrapper cases
remain passing evidence for their distinct corpus.

Channel audio-delivery extraction passes39 existing session checks. Strict Credo
now passes1221 source files without issues. The isolated MCP wire-limit retry passes
3 tests; the root run's initial handshake timeout occurred during concurrent native
compile, frontend checks and hosted runs. A clean root rerun is still needed.

## Outstanding-draft endpoint blocker

Independent fake-wire reproduction showed inferred settlement of an outstanding
partial is unsafe: commit 'first', draft 'yes', inferred final 'first yes', then
identical idle partial 'yes' reopens a phantom turn without new audio. A focused
regression failed red (7 tests, 1 failure, seed 319023). Changed draft recognition now
cancels the inferred candidate and waits for its commit or bounded commit timeout.
The earlier long hosted green runs relied on the rejected draft behavior and do
not accept the corrected endpoint path. Current long-input and configured-room
hosted gates remain open. Matching text across turns is deliberately not suppressed:
that would lose separately spoken identical answers. User clarification is pending
on holding the Scribe default switch or retaining its old acoustic endpoints (the
latter conflicts with the approved no-Silero VAD-off startup contract).

The revised endpoint suite initially had one stale fixture ordering: it sent a
new identical partial after the matching commit, correctly opening another draft
and cancelling settlement. Moving the duplicate keepalive before its commit made
the fixture match the intended contract. Final continuous/wrapper checks pass
18 tests (seed 218204), including post-commit draft timeout and separately committed
identical answers. The earlier interim/draft success is explicitly superseded.

Independent rereview accepts the revised draft rule (18 focused tests plus an
external duplicate-keepalive/identical-answer regression). The current official
ElevenLabs realtime API reference documents optional word timestamps as a delayed
additional committed-transcript event, not an endpoint-reason field. It also
explicitly describes keepalives repeating an uncommitted partial. This supports
waiting for stable commit evidence rather than interpreting idle draft text as
a new speaker turn. No additional protocol option was added speculatively.

The second full root run completed with all Call Engine, Calls, Gateway,
Artifacts, Persistence and Console tests passing. Its sole failure was the MCP
wire handshake's one-second acknowledgement timeout during concurrent checks;
the isolated three-case retry passed. A fresh sequential root completion run
(format, warnings-as-errors compile, strict Credo, unused dependencies, default
tests) is underway with no concurrent frontend/live runs. Current endpoint tests
are included in this fresh run; the previous root had loaded their earlier version.

The fresh sequential root run passed its MCP lane with no timeout. Final root
format/compile/strict Credo/dependency checks passed before test startup. After
that handshake-sensitive lane completed, the corrected two long hosted cases
were selected by file line39 to establish current safe endpoint evidence rather
than relying on the earlier unsafe-draft run. These are intentional acceptance
probes after a behavior fix, not repeated latency measurements.

The fresh root Call Engine lane passes 2,150 tests without failures (79 excluded),
including the corrected continuous draft handling. No later runtime changes were
made. The root Gateway/Persistence/Console lanes are still underway. Milestone
index now says implementation underway rather than planning only; the milestone
itself stays unchecked because endpoint and hosted/manual acceptance remain open.

Current safe long-input hosted evidence: both selected cases fail 'recognition did
not settle' within the ten-second post-input observation (seed 456239, 122.2 seconds
total; 2 tests, 2 failures, 2 excluded). This occurs with local VAD false and true. The
local option changes onset only, so it cannot repair the missing committed
endpoint. The failures are retained and are not excluded by weakening the test.
No further paid retries are justified without a changed endpoint contract.

Usage audit note: outer capability acceptance/settlement remains authoritative;
inner recognizer sessions disable usage, and recognition receives input once.
The existing SpeechToTextProjection labels every audio_duration_ms scalar as
provider_reported, including legacy locally counted durations. Continuous Scribe
also computes its scalar locally from submitted PCM. That existing provenance
projection limitation needs an explicit follow-up before claiming provider-billed
or provider-reported duration; no accounting rewrite or claimed billing evidence
was added in this checkpoint.

Final hygiene converts keyword-list bracket access in the two new coordinator/
runtime test files to Keyword.get, following the root AGENTS list-access rule.
This is a mechanical test-only change; the runtime is unchanged. A focused rerun
verifies identical assertions after formatting. The final root Gateway lane passes
without failures; remaining persistence/Console completion is pending.

## Final local verification

The fresh sequential root completion command exits0: format, warnings-as-errors
compile, strict Credo, unused-dependency check and full default mix test pass
(seed 913907). All umbrella applications pass, including Call Engine2150cases,
Gateway596cases and Console250cases. The preceding one-second MCP timeout does
not recur. Latest Lean build/oracle/replay also passes (seed 996288); its existing
source-gate model does not prove the new coordinator or Scribe heuristic.
Mechanical keyword-list test hygiene passes49 focused cases (seed 458330), with
no runtime behavior change. Full frontend tests/TypeScript/lint and rendered
source-edit/save evidence remain passing. Browser/Storybook processes started
for this task are closed.

Acceptance remains incomplete: corrected long Scribe tests fail in both onset
modes, the configured corpus lacks its appended brief word at the provider wire,
and manual web/carrier listening has not occurred. A user decision is pending
on the Scribe endpoint scope; the approved no-Silero default is not silently
relaxed. The milestone stays open, no commit/push was made, and pre-existing
latency/planning artifacts remain intact. The latency measurement still requires
VXPIPE_MEASURE_SCRIBE_LATENCY=1 and never runs in the default lane.

## Bounded post-commit draft flush

A fresh protocol probe established that an explicit commit request is supported
while Scribe remains in VAD strategy. Production now requests one such flush after
a post-commit draft stops revising for 1.5 seconds; only a nonempty committed
response permits inferred settlement. A missing response fails within five seconds.
No local acoustic detector or upstream strategy override is added.

Independent review found and reproduced blank-response promotion of uncommitted
words. A focused failing regression preceded the fix; ignoring blank segments
preserves all draft and timer state. Continuous tests pass 12 cases, and independent
wrapper/continuous review passes 21 cases with no remaining concrete flush blocker.

Ordinary hosted acceptance passes four cases (seed 513957): two distinct short
turns and a 45-second utterance, each with local VAD false and true. Those runs
preceded the blank-response guard, whose focused regression then passed. The
configured-room sequential hosted test still fails because the provider omits the
appended brief answer at the wire; the assertion is retained. The earlier parallel
configured run failed during protocol consolidation before testing. All subsequent
Mix checks run sequentially. Root completion and Lean are rerunning for the new
runtime behavior; frontend/browser evidence is unchanged.

See [protocol and flush evidence](20261011-0639-scribe-vad-flush.md). The endpoint
policy remains explicitly inferred_gap and cannot claim acoustic silence or
provider-semantic completion. Configured-room and manual listening gates remain
open, and no commit or push has been requested.

## Final verification after review

The sequential root command exits successfully: format, compilation with warnings
as errors, strict Credo, unused-dependency checks, Lean build/oracle/replay (seed
554342), and every default umbrella suite (seed 303467). No first-party failures
remain in these lanes. Lean still models the existing source gate rather than the
new coordinator or inferred Scribe endpoint. Frontend/browser evidence remains
valid because the flush change is backend-only. Documentation links pass.
Configured-room recognition and manual listening acceptance remain open. No commit
or push was made.

## Additional integration proofs

Coverage additions exercise already implemented contracts rather than introduce
new runtime behavior. The room test uses real Silero on public fixture PCM through
normal ingress with active agent playout: interruption precedes provider words,
partial/final recognition retains one caller reference, and the next model reply
occurs without a second interruption. The focused room suite passes (seed 683952).

Console activation tests now cover omitted/false/true through public tenant save,
publication, compilation and startup configuration, including inherited platform
and overriding tenant credentials. Omitted resolves false, explicit fields survive
publication, and invalid boolean values fail before publication with their field
path. The Console suite passes (seed 346956). Root format, warnings-as-errors
compilation, strict Credo, unused dependencies and both focused suites pass (seed
721116). Runtime code is unchanged, so preceding full-root/Lean/frontend evidence
remains applicable. Remaining replacement, PCM/usage, hosted and manual gates stay
open rather than inferred from these narrower tests.

## Source cutover decoder isolation

The remaining PCM gate exposed retained WebRTC STT Opus normalization history:
source hold/arm rotated receiver epochs but preserved SpeechInput's decoder and,
for stereo-to-mono Opus, encoder. A focused regression failed for unchanged decoder
identity; another failed because normalization reset failure still returned a hold
receipt (eight tests, two failures).

After a successful receiver hold barrier, SpeechInput now recreates normalization
resources while preserving ingress and format. Held packets never enter decoding,
so arm uses that fresh state. Decoder/encoder construction failure or an elapsed
deadline leaves the source held and uncertain, without an armable receipt. Nil and
unconverted inputs retain their ordinary behavior. No STS decoder/controller logic
is changed. Focused cutover and SpeechInput suites pass 17 tests (seed 668014).
PCM resampling is already stateless and maps absolute sample timestamps; it has no
resampler history to carry across this boundary. Full root/Lean checks are reopened
for this source-cutover behavior change.

The outer SpeechToText capability usage test now covers decoded-PCM sidecars with
VAD false and true. Both pass (seed 780038): each original payload reaches the
recognizer once, one outer attempt starts, and final audio/text deltas appear once
without inner observations. An initial fixture omitted policy installation;
initial_policy controls demand, while Enforcer installs the policy used for text
measurement. Applying that existing protocol corrects the fixture. No production
behavior changed for this usage proof. Tests use --no-compile, as documented by
mix help test, while the root default suite runs against the already built code.
The source-reset fix plus timestamp, sidecar, ingress and stale-inference evidence
complete the milestone's composite PCM/usage gate. This does not claim hosted
provider billing precision or resolve the previously recorded provenance limitation.

Permission replacement coverage now verifies both onset modes through the outer
capability's Enforcer protocol. Denial retires the old recognizer and cancels its
attempt; reopening creates a new allocation. Reusing the native reference does not
let a late old-allocation final settle the new turn. New final measurements belong
to the new attempt. Four usage/lifecycle tests pass (seed 72024). Initial test setup
incorrectly assumed provider indexes increase across replacements; the implemented
contract scopes indexes per allocation, with policy revision/generation fencing.
The corrected test explicitly checks those authorities. The combined room-output
interruption/replacement milestone gate is now covered.

The tagged ordinary live Scribe lane is extended to three turns (phrase, brief
answer, repeated identical answer), plus three seconds of real quiet PCM after each
settlement to detect phantom reopens. Long forced-segment coverage remains intact.
This supplies previously missing repeated-answer/idle evidence and validates the
reviewed blank-response guard on the hosted path. It runs via bin/livetests with
--no-compile against the already built runtime while the full umbrella suite runs;
no credential file is read by this agent. Hosted outcome is pending.

The expanded ordinary hosted Scribe lane passes all four cases (seed 397253,
152.9 seconds). Both onset modes preserve one 45-second turn across segments and
three distinct turns containing a repeated identical brief answer. Three seconds
of real quiet PCM after every short-turn settlement produces no semantic events.
The runtime retains Scribe v2 realtime, English and VAD strategy. The current
reviewed blank-response guard is in this run. The milestone's ordinary live gate
is complete; configured-room corpus accuracy and manual listening remain open.

## Final checks for source-cutover isolation

The sequential root completion command passes format, compilation with warnings
as errors, strict Credo, unused dependencies, Lean build/oracle/replay (seed 550001)
and the full default umbrella suite (seed 791499). The usage/lifecycle test file
was added after the root Call Engine lane loaded tests; its four cases pass in a
separate focused run (seed 72024), and final format/Credo checks pass. No frontend
runtime changes followed the existing rendered/TypeScript/lint proof. Lean retains
its source-gate coverage limit rather than proving ASR heuristics.

Checkpoint B PCM/usage, checkpoint C interruption/replacement, checkpoint D API,
and checkpoint E ordinary hosted Scribe gates are now verified. Remaining gates
cover configured-room recognition, quiet/noisy listening, the selected carrier call
and restart/old-publication preparation. No commit or push was requested.

## Fresh-VM publication restart compatibility

The tagged restart check saves, publishes and reloads real database-backed call
spec revisions for omitted, false and true. A pre-change compiled snapshot is
represented by historical absence of the optional field. Snapshots carry no private
credentials. Two fresh mix-run VMs load them through ResolvedPlanCodec, verify
unchanged stored bytes and identity, prepare startup and actually start/ack/retire
each STT session. Historical Scribe remains native/manual/local_gap; current
snapshots use the shared onset setting and automatic VAD/inferred_gap. The child
uses a synthetic credential resolver and a fake socket, never hosted recognition.
The first runner attempt omitted its own :omitted vocabulary atom before safe
outer-envelope decoding; declaring controlled modes fixes that fixture problem.

Focused restart integration passes (seed 52344). Root format, warnings-as-errors
compile, strict Credo, unused dependencies and restart/usage focused checks pass
(seed 204280). The nested Console formatter requires child formatting options;
that formatting mismatch was corrected. No runtime code changed. This proves
restart preparation, not ASR accuracy or manual listening. The fixture is explicitly
integration-tagged to keep fresh-VM startup out of the default lane.

## Configured-room outbound integrity

The selected hosted trace verifies all 774,400 fixture bytes in order on a single
socket (seed 906572). The word-fidelity assertion still fails, and no provider
partial/commit contains the appended brief answer. Only byte counts/digests/socket
identity are traced; raw PCM, transcripts and credentials are not logged. This
proves integrity through the socket send API rather than server acknowledgement.
The repeated corpus has an ASR accuracy limitation; the common turn coordinator
cannot invent missing words. The failing acceptance assertion remains unchanged.
See [room-audio evidence](20261011-0737-scribe-room-audio.md).

The live telephony harness documentation establishes a machine-owned Telnyx-to-
Telnyx self-call route. No personal destination is needed for automated carrier
verification. The selected existing live_telephony_telnyx case uses published specs
whose omitted onset field now resolves false, proving reciprocal carrier greetings
through ordinary Deepgram input and durable closure. It is invoked through
bin/livetests; the runner discovers existing resources and performs no purchase or
provisioning. This does not substitute for the specified human listening/barge-in
pass. The selected result is pending.

Final test-only restart/outbound diagnostic checks pass root format, compilation
with warnings as errors, strict Credo, unused dependencies and selected restart,
outer usage/lifecycle and fake configured-room tests (seed 16574). Production runtime
is unchanged since the full default umbrella/Lean pass. The hosted diagnostic keeps
its word-fidelity failure and its exact socket-input evidence. Human listening
remains unperformed. The owned-number carrier command is still running in setup;
its active handle is polled rather than restarted.

## Carrier endpoint blocker

The selected owned-number Telnyx command exits before the Mix test starts: public
Funnel relay readiness fails after 300 seconds. Public Google and Cloudflare DNS
both return NXDOMAIN with zero answers for the configured test hostname. Read-only
bin/livetests tools:status confirms the runner's test node is stopped after cleanup.
No carrier test result or manual listening success is claimed. This is an external
endpoint prerequisite, not a speech-code failure. No blind rerun or number purchase
is attempted. The credentials file is never inspected.

An acceptance-scope question is now pending: retain the configured-room/listening
holds, or explicitly accept the verified ASR limitation and defer listening. The
milestone requires unresolved gates to stay open; no answer is inferred from
elapsed time. Core runtime, fresh-VM restart, default root/Lean and selected live
onset evidence remain recorded. This turn made progress through actual fresh-VM
proof and outbound-integrity diagnosis; the goal remains active.

## Verification scope correction

The user clarified that telephony is unnecessary for verifying this speech change.
The carrier check was an extra acceptance requirement introduced during this work;
it has been removed from the milestone and index. The earlier Funnel DNS failure
is historical diagnostic evidence, not a prerequisite or remaining blocker. No
carrier call was placed. Required verification uses streamed audio and web voice
checks. Configured-room ASR fidelity and quiet/noisy web voice listening remain
unresolved; this scope correction does not claim they passed.

## Resumed acceptance checks

The user asked to complete the milestone with required tests and confirmed that
telephony is unnecessary. The 300 ms intra-utterance pause diagnostic still loses
the brief answer in hosted Scribe wire text, with exact socket-input integrity
verified (seed 901442). Original fixture and unchanged fidelity assertion retained.
See the updated room-audio research record. Required regression checks are rerun
on the current worktree; no carrier test is selected.

Hosted background-noise cases pass with local VAD false and true (seed 625027,
27.9 seconds). The deterministic public-speech mixture and noise-only controls
prove bounded synthetic-noise behavior without claiming human microphone quality.
WebRTC/RTVI peer tests pass in both onset modes (seed 311960). Blank native onset
leaves agent output active; first transcript interrupts once, then final caller
text and the next model reply reach the client. The first attempt hit the inherited
100 ms TTS startup assertion under concurrent verification; its project-owned
acknowledgement now waits at most five seconds. Runtime behavior is unchanged.

The strengthened WebRTC test starts actual agent audio playout and waits for
bot-started-speaking plus its in-progress output before the microphone/onset
checks. Both modes pass with neighboring web contracts (seed 635784). The first
stronger run incorrectly treated the expected playout-progress message as an
unexpected speech event; consuming that expected acknowledgement fixes the test
protocol, with no runtime change. Frontend tests, TypeScript and lint pass again.
The default umbrella suite remains running in session 26453.

## Final resumed regression evidence

The full default umbrella suite passes (seed 673225), including all Gateway
cases after the added onset-mode parameterization. Root format, warnings-as-errors
compilation, strict Credo and unused-dependency checks pass; the Lean lane passes
(seed 569839) with its previously recorded source-gate coverage limit. Final
format/Credo checks also pass after the stronger web playout assertions. The
latest web playout cases pass separately (seed 635784). Frontend tests, TypeScript
and lint pass. Changed Markdown links resolve and git diff --check passes.
No live telephony ran and no commit or push was requested. Selected restart/local
room/outer-usage integration verification also passes (seed 903047).

Completion audit: all implementation checkpoints have existing focused evidence,
API defaults to false, explicit true is API-only, and there is no Console toggle.
Acceptance remains unproven for the configured-room appended-answer fidelity case
and human web voice listening. The failed 300 ms pause diagnostic rules out a
simple splicing explanation without changing the assertion. Scope questions remain
unanswered; their absence is not an acceptance exception.

## Acceptance handoff

Revalidated the current milestone and completed regression outputs on the next
goal continuation. The previous turn made progress through hosted noise coverage,
stronger WebRTC playout assertions and final regression verification. No process
from that run remains active. Added the focused
[Scribe appended-answer issue](issues/scribe-appended-short-answer.md) with the
existing reproduction, exact outbound evidence, failed pause hypothesis and
server-acknowledgement limit. Its status explicitly retains the milestone hold;
creating the issue does not infer permission to defer it. The milestone now lists
the remaining human listening observations concretely. No runtime or test behavior
changed, and no paid provider rerun was made without a new diagnostic question.

## User-clarified completion scope

The user accepted the missing final word as tolerable for this milestone and
specified that the first partial must serve as the speaker-start event. Explained
that later partials can update a turn, but the missing answer never appeared in
this observed fixture. Applied the clarified speech-start criterion to the passing
canonical-ordering, hosted onset and WebRTC playout evidence. Updated the milestone
and index to complete. Human listening stays explicitly unperformed as follow-up;
recognition fidelity remains an open issue with its original tagged assertion.
No runtime/test changes, new live requests, commit or push were made. Previous
root/Lean/frontend and focused/integration evidence remains applicable. This
supersedes the earlier acceptance holds without claiming their tests passed.

## Commit checkpoint

The user requested the completed changes be committed. Reviewed the exact milestone
path inventory and existing verification evidence; all changes belong to this
coherent speech-start checkpoint, including its research, tests and documentation.
Root/Lean/frontend and focused/integration checks passed before the documentation-only
acceptance updates. The Scribe accuracy issue remains a known failing tagged live
case; human listening is an unperformed follow-up. Neither is reported as passed.
The latency measurement stays opt-in. No new provider request or push is part of
this commit checkpoint.
