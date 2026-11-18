# Universal structured replies across LLM integrations

Status: checkpoints A and B implemented, with configured Google/OpenAI conversation
and controlled Hangup acceptance recorded. Checkpoints C–F and release remain open. The milestone index
owns ordering. User direction, 2026-11-18: no structured-response allowlist;
every LLM integration must support the common agent reply contract.

Approved scope change, 2026-11-18: after the live runner reported a missing
`ZENMUX_API_KEY`, the user directed “skip zenmax for now. continue with the rest”.
Defer Zenmux live acceptance and continue the other five integrations. Zenmux stays
in deterministic conformance and implementation coverage. Report its live result
as deferred, never passed; references below to all-six live evidence have this
explicit exception for the current run.

## Runnable outcome

An author selects any configured LLM integration, saves and publishes a valid
call spec, and runs an agent conversation using the same `agent_mode`/`message`
contract. It speaks, stays silent, calls Hangup and other authorized native tools,
handles later results and continues with truthful settled history. No provider or
model is rejected solely because it is absent from a structured-reply allowlist.
Google AI Studio with `gemini-3.5-flash-lite` is the explicit regression case,
not a new special-case permission entry.

## Prerequisites and design sources

Read before implementation:

- [Universal reply design and investigation](../../docs/design/universal-agent-replies.md).
- Completed [structured messages/history](structured-agent-messages.md), including
  [original contracts](../../docs/design/structured-agent-messages.md) and its
  [implementation evidence](../20261116-1642-implement-structured-messages.md).
- Completed [ReqLLM runtime](reqllm-agent-runtime.md),
  [shared participant tool execution](shared-participant-tool-execution.md), and
  [context compaction/native routing](context-compaction-and-native-fallback.md).
- Completed [draft/publication workflow](call-spec-drafts-and-publications.md).

This milestone supersedes only the prior selected-profile eligibility policy.
It precedes the remaining [voice behavior work](voice-agent-turns-and-listening.md)
in the index. Precise speech timing, a new voice policy, new provider integrations,
new credentials, STS protocol changes and schema-format changes are not prerequisites
or scope. Existing tenant/platform visibility rules remain in force.

## Contracts and completion rules

- One shared schema, decoder, request lifecycle and typed result across integrations.
  Native schema encoding may differ; speaker/listener and tool semantics may not.
- Remove identity-based protocol gates from plan validation, session configuration,
  request projection and replay compatibility. Keep legitimate independent validation.
- Native JSON Schema is optional. A portable instructed/validated JSON path is
  required when native schema plus tools is unavailable. No approval list disguised
  as capability flags, catalog filtering or model-specific tests.
- Retain the full authorized native tool set on every round. Do not replace tools
  with a forced schema function, invent tool success, replay side effects or drop
  signatures/reasoning needed for continuation.
- No partial or invalid response reaches speech or settled history. Preserve output
  bounds, cancellation, deadlines, usage, null semantics and host settlement.
- Proposed one-attempt correction is bounded as described in the design. Resolve
  and document its precise request/history accounting before code, with no retry
  after tool dispatch and no tool dispatch from repair responses.
- Historical legacy publications remain readable and runnable under their pinned
  semantics. No live provider call during save/publish; no automatic downgrade.
- Evidence includes all six installed LLM integrations. Missing credentials or
  failing acceptance leave the relevant checks open; they never justify restoring
  an allowlist or declaring the whole milestone complete.
- Every checkpoint follows red-green-refactor and keeps implementation, focused
  tests and checkpoint notes together. Early checkpoints are runnable locally;
  production release waits for the complete acceptance checkpoint.

## Checkpoints and dependency order

| Checkpoint | Runnable result | Depends on |
| --- | --- | --- |
| A | One portable modern dialogue path, without identity gates | Prerequisites above |
| B | Google AI Studio and existing OpenAI run full tool conversations | A |
| C | Remaining installed LLM integrations run the same contract | B |
| D | Save/publish, activation and historical publication flows work end to end | C |
| E | Registry-wide conformance and configured-call evidence are complete | D |
| F | Verified production release and maintained integration requirements | E |

## Checkpoint A — Shared contract without the allowlist

**Exit:** local real-adapter requests for a non-allowlisted model can produce
validated dialogue and native tool rounds through the ordinary Session, without
any provider/model eligibility table.

- [x] Add failing public-boundary tests for non-OpenAI models and unfamiliar valid
  model IDs in plan compilation and modern Session configuration. Enumerate installed
  LLM manifests so a newly added integration cannot silently escape coverage.
- [x] Replace `DialogueProfile` identity eligibility and callers in AgentProtocol,
  SessionConfiguration and RequestProjection with shared protocol/options validation.
  Separate OpenAI replay compatibility from the deleted allowlist. Preserve unknown
  protocol, idle-on-STS and other real configuration errors.
- [x] Introduce the semantic request strategy boundary and portable instructed-JSON
  path using the existing schema/prompts. Provider identity may select wire encoding,
  never permission to use the reply contract. Keep the full tool set and strict decoder.
- [x] Resolve private strategy pinning and bounded correction details in the design;
  implement and test budgets, cancellation, repair context exclusion, usage and
  side-effect prohibitions. Invalid final output remains a typed failure.

Acceptance: strict valid/invalid/null/duplicate/extra-field cases, partial streams,
refusal, over-limit output, stale completion, cancel during repair, and absence of
speech/tool effects on invalid or repair responses. Standalone legacy sessions remain
unchanged. Do not enable a second tool loop to implement recovery.

## Checkpoint B — Google AI Studio and OpenAI conversation parity

**Exit:** configured Google AI Studio and OpenAI agents pass the same multi-turn
scenario through actual request projection, streaming, tool execution and history.

- [x] Capture actual encoded buffered and streaming requests for Google AI Studio
  and OpenAI. Prove schema placement, instructions, full native tools and decoding;
  do not infer correct wire output from high-level SDK options.
- [x] Implement native schema encoding where supported through ReqLLM's existing
  surfaces, with the portable path for unsupported combinations. Keep strategy
  stable across rounds. Add reproducible dependency changes/patches only if a
  demonstrated gap requires them; never edit `deps/` as the delivered fix.
- [x] Generalize replay dispatch while preserving bounded opaque metadata, source
  binding and exact native call/result pairing. Cover Google signatures/role folding
  and the existing OpenAI reasoning/phase regression without leaking replay into
  speech, transcript storage or summaries.
- [x] Reproduce earlier Google malformed/fenced-output and unwanted-tool scenarios
  with all tools present. Run the user's `gemini-3.5-flash-lite` selection with a
  synthetic receptionist fixture (no copied caller information), including a real
  controlled Hangup invocation and a separate continuing-tool conversation.

Acceptance: short/long dialogue, listener/null, listener cue, native tool call,
acknowledgment, unrelated input, async completion, subsequent reply, idle timeout
and cancellation. Compare logical and provider-normalized history prefixes. Record
request counts, failures, latency and usage; do not select only passing runs.

## Checkpoint C — Every remaining LLM integration

**Exit:** DeepSeek, Fireworks, OpenRouter and Zenmux each run the same modern
conversation without a new per-model permission entry.

- [x] Apply the common strategy boundary to all four integrations. Audit actual
  transport capabilities and native routing options rather than assuming their
  OpenAI-compatible endpoints share all OpenAI semantics.
- [ ] Preserve each integration's required reasoning/signature/tool metadata across
  buffered and streamed responses, compaction, interruption and recovery. Check
  that router changes cannot reuse replay scoped to a different downstream model.
- [ ] Exercise a representative configured model for each integration and the
  portable path independently of native schema support. Test unavailable native
  metadata without a save/publish rejection or silent legacy downgrade.
- [x] Make the common harness fail if any registered LLM integration is omitted.
  Record native/JSON-mode/portable paths actually exercised, model/transport
  identifiers and dependency versions; model names in fixtures are evidence,
  never production eligibility configuration.

Acceptance: the B conversation matrix for every integration, plus routed provider
failure, incompatible replay, malformed JSON, no repeated tool effects and truthful
usage. Upstream unavailability leaves live evidence pending rather than fabricated.

## Checkpoint D — Authoring, activation and compatibility

**Exit:** the configured integration selected in the editor can be saved, published
and used through Console/API admission, with historical publications preserved.

- [ ] Add failing tests at Calls, Persistence and Console boundaries showing valid
  Google and other LLM specs pass both draft save and publish without the removed
  profile error. Invalid source/credentials/options still fail without inserting
  a revision or discarding browser edits.
- [ ] Cover preparation, activation restart, transfer, compaction and newly saved
  protocol snapshots. Keep earlier publications' legacy semantics, and reject
  malformed/unknown bundles. Review sample installers' explicit legacy selection;
  do not use samples as a hidden compatibility bypass.
- [ ] Remove obsolete OpenAI-profile-only UI guidance and provider documentation.
  Preserve configured integration labels, tenant/platform permissions and saved
  inaccessible references. Do not filter the catalog by schema-native capability.
- [ ] Inspect a rendered configured editor and a real controlled call for Google AI
  Studio plus a contrasting integration. Verify only speech text appears in the
  transcript; control JSON and private replay never appear in user-facing output.

Acceptance: compile/save/publish/read/restart, unchanged public source shape,
legacy read/prepare, unknown protocol failure, no live inference on authoring,
correct error field routing and authorized visibility.

## Checkpoint E — Complete conformance evidence

**Exit:** all six integrations have deterministic conformance and configured live
acceptance evidence, with no excluded integration and no remaining allowlist.

- [ ] Run one shared adversarial matrix: ordinary/tool/async/idle rounds, malformed
  and oversized output, duplicate keys, refusal/truncation, unknown mode, null,
  opaque replay, cancellation, deadline, bounded correction and recovery.
- [ ] Run tagged live provider cases through `bin/livetests run`, using permitted
  configured credentials without reading or modifying the protected live-provider
  environment file. Add missing shared cases to existing provider lanes. Report
  unavailable credentials explicitly; keep that integration's gate unchecked.
- [ ] Record the six-integration evidence matrix, full tool availability, actual
  submitted schema/JSON strategy, immutable history and absence of repeated side
  effects. Include the exact Google model reported by the user. Define a fixed
  scenario/repetition plan before running, and retain failed attempts.
- [ ] Run required root format, compile-with-warnings-as-errors, strict Credo,
  umbrella tests and unused-dependency checks; relevant frontend/type checks and
  rendered inspection; Lean if source-cutover or speech-state behavior changes.
  Resolve project-owned failures and distinguish unrelated failures in evidence.

## Checkpoint F — Documentation and release

**Exit:** the accepted shared implementation is committed, deployed and verified;
future LLM integrations inherit the same contract and conformance requirements.

- [ ] Update the durable design, integration authoring guide, usage documentation,
  prior profile-policy notices and this milestone/index together. Explain generic
  support versus actual upstream request failures without promising infallible JSON.
- [ ] Verify the release contains no provider/model reply allowlist, no substitute
  catalog exclusion and no implicit legacy fallback. Retain ordinary model and
  credential validation and the shared strict decoder.
- [ ] Commit the accepted implementation before building/deploying `vxpipe.service`;
  retain a recovery image, run packaged migrations and verify image revision,
  public health and frontend assets. Use an authorized synthetic call for smoke
  verification rather than modifying the user's spec or placing an unsolicited call.
- [ ] Commit release evidence and synchronize completion status only after every
  exit is verified. Recovery uses the prior image; this milestone does not require
  rewriting stored call specs or credentials.

## Specification review — separate from implementation

Reviewed locally on 2026-11-18 against source, installed dependency code, historical
Google/OpenAI evidence and current primary provider documentation. No independent
agent review, live inference or implementation verification is claimed.

The review identified and incorporated: duplicate eligibility gates; OpenAI request
options in a shared path; replay coupled to identity eligibility; a generic fallback
needed for universal support; unsafe synthetic-schema-tool shortcuts; side-effect
risks in retries; registry-wide coverage; routed replay compatibility; legacy
publication pinning; and save/publish/UI parity. Dependencies are completed milestones
already preceding this entry; voice policy and external credentials are not hidden
implementation dependencies. Credential absence blocks live acceptance, not design
or an integration's eligibility. Proposed recovery/pinning details must be resolved
in A before implementation, not silently invented in a later provider checkpoint.

## Implementation evidence — A, first subcheckpoint

Registry-driven Session configuration and plan compile/pin tests cover all six
installed LLM integrations; resolved future model IDs exercise identity-independent
Session admission. Initial tests failed on the former eligibility checks. Google
modern save/publish also failed before removal and now passes with preparation;
legacy publication and idle-on-STS restrictions remain covered. A real ReqLLM HTTP
fixture through Session validates Google dialogue with host settlement. OpenAI
Responses schema/tool wire checks remain green.

Focused verification: 24 runtime provider tests, 7 plan/idle tests and 23 persistence
tests pass (2 persistence integration exclusions). This is local deterministic
evidence, not live provider acceptance. At this first subcheckpoint, correction
and the blocking-tool declaration contract were pending; both are implemented
in the following subcheckpoint.
Astra xhigh review found no remaining issues in this subcheckpoint after three
reproduced corrections. Full umbrella verification remains in progress.
See [checkpoint labnote](../20261118-1444-implement-universal-replies.md).

## Implementation evidence — A, bounded correction

The private bounded_once_v1 policy is captured with restartable Session options.
Its first-round-only correction shares the original worker/deadline, preserves
native tool declarations, rejects tool dispatch from repair, meters both attempts
and excludes malformed output/correction instructions from settled history.
Explicit reported-output provenance, finite remaining output and measured input
capacity are required. Unknown usage disables correction, never protocol admission.
Modern blocking continuations retain tools; legacy behavior is unchanged.

Real-adapter fixtures prove OpenAI correction caps of 100 then 90 and Google
native tool/signature/result continuation through Session. They exposed and fixed
transport token-option projection and a ReqLLM buffered Google signature loss.
The delivered exact-source dependency patch is integrated into setup, CI and
production build guidance, with checksum/repeatability tests.

Astra xhigh re-review found no remaining actionable issues after reproducing and
fixing native option cap precedence, namespaced history overrides and setup fixture
failures. Independent correction/wire tests, 34 setup tests and the patch test
pass. Root static gates pass; the full umbrella rerun is still in progress.
No configured live-provider acceptance or deployment is claimed.

## Implementation evidence — B, native wire subcheckpoint

Actual local HTTP captures exercise Google and OpenAI buffered and streamed
schema encoding, full tools and output caps. Google selects native schema plus
tools through an offline SDK preparation probe; unsupported combinations keep
portable JSON. Raw malformed/fenced/duplicate output retains the shared strict
decoder, and real named tools retain signatures. The pinned dependency patch
corrects explicit cap inflation, synthetic Google schema tool chunks and private
thinking text concatenated into public JSON. Source-state upgrade and repeat
application are tested. Replay generalization and configured live conversations
remain unchecked; these wire fixtures do not constitute live acceptance.

Final Astra xhigh re-review found no remaining actionable issue in this
subcheckpoint after proving/fixing private thought contamination and both nested
and flat builtin-tool options. Independent 8 tests and patch preparation pass;
final runtime child 185 tests pass (9 excluded). Broader umbrella verification
continues, and the remaining B–F gates stay open.

## Implementation evidence — B, Google replay and pairing

A provider replay dispatcher retains OpenAI's existing reasoning/phase behavior
and adds bounded Google ordered-Part replay. Canonical byte ranges and call indices
preserve public/private/empty signed Parts without alternate public text/arguments.
Source/model binding rejects redacted, removed or incompatible history. Actual
buffered and streaming continuations verify original Parts, native ID provenance,
call/result pairing and role folding with an unchanged prior history prefix.

Independent Astra xhigh review is clean after proved fixes for public-part and
empty-carrier signatures. Final independent 10 tests, fresh/repeat/prior-state
patch upgrades and root static gates pass. Live receptionist/Hangup and the full
configured conversation matrix remain pending, so checkpoint B is not complete.

## Live acceptance investigation — gate still open

The [fixed live plan](../../docs/design/universal-replies-live-plan.md) and
[retained metrics](../../docs/design/universal-replies-live-evidence.json) record
all initial and diagnostic attempts. Initial fixture instructions were incomplete;
corrected tests compose the captured protocol, attribute caller input and publish
pending state before acknowledgment. The corrected trial completed the Google
portable streaming conversation, while native Google still looped on tools and
buffered portable failed a later reply. Both OpenAI cases in that trial hit an
incorrect case-sensitive status assertion on valid lowercase text.

Independent review then proved overly permissive semantic checks and those checks
were tightened. Earlier per-step completed outcomes mean runtime completion only;
case results and failure lists remain retained. No passing run of the tightened
fixture, real-room Hangup, all-six-provider acceptance or deployment is claimed.
These findings do not close checkpoint B or change the index status.

## Implementation evidence — B, configured acceptance

The final fixed six-case conversation run passes Google configured/explicit portable
and OpenAI in buffered/streamed modes. Each case covers all ten steps, one native
lookup, truthful running acknowledgment, unrelated input, trusted completion, idle,
cancellation and explicit resumption. Prior failures remain in the linked evidence.
Google selects portable encoding from resolved metadata; native encoding and
ordered replay remain covered by actual local HTTP fixtures, with full tools and
logical/provider-normalized history prefix checks. OpenAI native wire/replay
regressions remain green.

Two additional Console live cases save/publish and prepare new encrypted-credential
synthetic plans, invoke the real authorized Hangup action, observe its ending result
and monitor room teardown. Both Google and OpenAI pass. No telephone destination or
user-owned spec is touched. A deterministic full-helper streaming recovery case
and semantic adversarial regressions pass. The full umbrella rerun exposed a
separate MCP test ordering race; its test-only handshake fix passes 100 independent
repetitions after six failures in the original 100. Final Astra xhigh acceptance
review is clean. Full umbrella verification continues; these checks do not close C–F.

## Implementation evidence — C, direct reasoning replay in progress

The [Chat Completions transport investigation](../../docs/design/universal-replies-chat-replay.md)
records the direct DeepSeek/Fireworks reasoning codec and the narrow reproducible
Fireworks SDK field-filter patch. Real outgoing HTTP tests cover both modes,
including multi-event reasoning, native calls/results, full tools and rejection of
changed source/model replay. Initial four field-loss failures and a later pair of
stream-chunk failures were reproduced before their fixes. Router replay, ordinary
host-settled reasoning, full lifecycle coverage and configured live acceptance
remain pending; no C task is checked off by this incremental change.

## Implementation evidence — C, router transport and registry coverage

All four remaining transports now have actual buffered/streamed HTTP coverage.
Router replay preserves exact ordered metadata, binds source/options, pins the
reported model before subsequent requests and disables alternate-model fallback
while private history remains. Modern decoding cannot invent native calls from
quoted private reasoning. The shared six-provider harness is registry-checked;
its [transport matrix](../../docs/design/universal-replies-chat-replay.md) records
model IDs, strategies, dependency version and current live outcomes. C tasks 1 and
4 are complete; lifecycle and full enabled live acceptance remain open.

Final Astra xhigh review is clean after reproduced fixes for malformed fields,
quoted tool syntax, blank origins and nullable text carriers. Independent checks:
54 adversarial cases, 16 final regression controls, two legacy cases and all five
prior patch upgrades pass. Runtime suite: 240 tests, zero failures, 25 live
exclusions. Root static gates pass. The prior full umbrella's WebRTC teardown
race is fixed and reviewed separately; its intermittent phone recovery timeout
remains under investigation. No full-green umbrella or release claim is made.
