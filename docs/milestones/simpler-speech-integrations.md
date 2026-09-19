# Simpler speech integrations

Status: checkpoints R and A accepted; native TTS checkpoint D is next.
Implementation: **2 of 9 checkpoints complete**. The revised order is
**R → A → D → B → C → E → F → G → H**, preserving existing checkpoint identities.
The user-requested baseline commit records the experimental standalone prototype and evidence;
it does not accept a checkpoint. The final room-owned architecture remains pending. The
[startup isolation and load evidence](../speech-startup-isolation.md) demonstrates unrelated
session startup exceeding its budget in the first prototype. The corresponding
original-path isolation controls passed; this is not a demonstrated defect in `main`.
Existing rooms still use the original path.
The R prototype initially failed its adoption-authority test and was paused under the user's
tested-instability rule. The user authorized the fix and load verification. The old lease's
close now rejects after adoption, while the current consumer owns close and failure delivery.
The [repair report](../speech-adoption-fix.md) records 16,236 adoption-load turns and two
68,400-turn legacy/native comparisons. That bounded repair did not accept R. The later
[deadline and failure-containment work](../speech-deadlines-and-failure-containment.md)
completes R's remaining gates with independent review, focused tests, load and umbrella checks. The [original failure labnote](../../labnotes/20260919-1839-scoped-speech-ownership.md)
retains the reproduction. Commit `343829c` preserves the pre-R experimental baseline.
The later [scoped speech experiment](../scoped-speech-experiment.md) exercises a test-only
semantic bridge through real rooms before approval. It provides behavioral/load evidence;
it does not establish final room nesting; room migration remains pending the native A/D gates.

Prerequisites: the implemented speech path in [Call-Spec-driven calls](call-spec-driven-call.md),
[Local Morse providers](morse-code-audio-providers.md),
[Opening audio](opening-audio-and-call-lifecycle.md),
[Live mixing/media policy](live-mixing-and-media-policy.md),
[Usage observations](usage-and-billing-observations.md), and
[Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md).
Retain the implemented readiness/preparation contracts linked below; the remaining live-carrier
acceptance in other milestones is not a prerequisite for changing the speech boundary.

Design sources:
[revised ownership proposal](../speech-session-ownership.md),
[semantic contract](../speech-provider-contract.md),
[provider comparison](../speech-provider-comparison.md),
[architecture](../architecture.md),
[inline selections](../inline-provider-selections.md),
[current platform/tenant credential inheritance](../platform-and-tenant-services.md),
[readiness resources](../readiness-resource-contract.md),
[typed interruption](../typed-turn-interruption.md),
[spoken barge-in](../spoken-barge-in.md),
[opening contract](../opening-audio-contract.md),
[transport privacy](../speech-transport-privacy.md), and
[resolved egress-buffer issue](../issues/tts-egress-buffer.md).

## Runnable outcome

A developer writes one documented provider-session interface for STT or TTS, uses reusable
event/audio delivery helpers, and registers it in the closed catalog. The developer does not
implement a second public transport interface, manufacture JSON for local processing, or read
the room state machine to determine when an utterance is finished.

Both existing Morse and Deepgram selections run through that boundary. A direct-PCM Morse
room still recognizes input, invokes the existing local model fixture, synthesizes a response,
plays it fully and survives an interrupted response followed by another turn. Hosted speech,
opening audio and private transfer speech retain their existing externally observable contracts.

The comparison informs conformance tests; it does not add five hosted integrations. Gemini
Live and batch transcription remain separate future contracts. Dedicated request-based TTS
is demonstrated using a synthetic provider with no persistent connection or started event.

## Contract and scope

The [design](../speech-provider-contract.md#proposed-author-facing-interface) proposes four
required STT functions and five TTS functions: configuration, supervised startup, audio input
or speak/cancel, and close. Configuration returns a descriptor instead of several metadata
callbacks. Providers emit typed semantic results through a bounded channel private to their allocation.
Reusable helpers never imply a shared execution process or provider-start queue.

Existing approved contracts remain authoritative: room-owned attribution and turn admission,
privacy-interval enforcement, fresh readiness, scoped credentials, bounded buffers, locally
confirmed playback, usage provenance, independent opening TTS and explicit provider failure.
The new public interface and internal module names are proposed by this milestone.

Keep scope in `vxpipe_call_engine`; do not extract another application or add a dependency
unless implementation demonstrates a separate need and records it. No Call Spec schema or
public provider-name migration is intended. No automatic reconnect, request replay, speech
fallback, new VAD, new codec/resampler, browser protocol, provider account or model is added.
Incremental TTS text input and manually finalized STT need their own authorized consumers.

## Experiment findings carried into acceptance

The [scoped experiment](../scoped-speech-experiment.md) passed 12,996 measured ordinary turns,
12 loaded control scenarios and 11 focused tests. Its scopes belong to the test supervisor;
legacy connector/output machinery remains in the real-room bridge. It proves the tested
behavior, not final room ancestry, all permission boundaries or a completed checkpoint.

- **Ownership:** room supervision and participant attribution remain distinct. Keep explicit
  participant, connection, activation, purpose and generation bindings. The room must still
  close the correct tree on departure/replacement; moving every capability beneath a
  participant supervisor is outside this plan.
- **Latency:** no overall speedup is established. In the 32-call burst follow-up, turn-end
  p95 was 4.513 ms existing versus 5.708 ms scoped; first-audio p95 was 1.680 versus 2.121 ms.
  Retain the earlier scoped sink-finish p99 of 213.800 ms and its failure to repeat, alongside
  the favorable paced results. The user accepts about 1 ms of added processing latency for
  reliability (2026-09-19); an across-the-board speedup is not an acceptance requirement.
  Define metric-specific tail/deadline budgets before B migrates room input and evaluate both
  native directions. This tradeoff does not waive queue, loss, cleanup or fault-isolation gates.
  Better hardware is a hypothesis,
  not an explanation for the observed differences or a waiver of regression checks.
- **Capacity:** 32 was the highest ordinary burst concurrency tested, not a capacity limit.
  Repeated ordinary paced trials reached 8 calls; the control lane had 32 paced calls plus two
  control calls. Record machine/runtime settings and workload boundaries with future reports.
  Any capacity claim needs a separate bounded, sustained paced ramp with latency/error gates,
  scheduler utilization, queues and memory, plus operating headroom. Short Morse runs do not
  establish hosted/network/codec production capacity.
- **Failure handling:** the prototype proves specific held-start, deadline, owner-loss,
  failed-credit and interrupted-replacement behavior. It does not establish faster recovery
  than `main`. R tests allocation/capability failure separately; B/E repeat at real room
  boundaries. Report teardown and explicitly authorized replacement readiness separately;
  temporary allocations never imply automatic reconnect, fallback or replay of lost speech.
- **Simplification:** identify lifetime-only monitor/kill/task bookkeeping that local OTP
  supervision replaces, and remove it as its callers migrate. Preserve readiness/event order,
  lease monitors, generation fencing, privacy, usage and playback responsibilities. There is
  no demonstrated net code reduction yet; a compatibility prototype cannot establish it.

## Delivery strategy

Continue **R → A → D → B → C → E → F → G → H** in that order. R replaces the rejected
global ownership; both native directions must pass
isolated lifecycle and latency checks before room integration. Existing A1/A3 evidence is
retained, but does not bypass R or the revised A/D gates. Each checkpoint has an executable
vertical outcome, a small set of file changes, a red test and an exit gate. The standalone provider slices deliberately
prove real audio before altering room orchestration. Existing paths remain usable during them.

Temporary bridges exist only while one built-in provider still uses the old boundary. Remove
the STT bridge in checkpoint C and the TTS bridge in F. Do not expose bridge selection in Call
Specs or keep two long-term configuration APIs. Preserve user changes in the worktree.

For each checkpoint: run the smallest owning-child test red for the stated project behavior,
implement it green, then refactor; update relevant docs and labnotes. Run the broader relevant
suite and all five root gates before treating that checkpoint as usable. The user authorized
checkpoint commits; no checkpoint may be committed as complete while its acceptance is red.

Paths in the task lists are relative to `apps/vxpipe_call_engine/` unless stated otherwise.
`lib/vxpipe/call_engine/` is abbreviated `lib/` below. Proposed files are explicitly described
as new; naming may be refined without changing the contracts or checkpoint acceptance.

| Checkpoint | Runnable slice | Candidate commit subject |
| --- | --- | --- |
| R | Independent owned trees start/close safely while unrelated providers stall. | Restore scoped speech ownership and bounded admission |
| A | Native Morse STT uses the scoped boundary with measured bounded input. | Introduce semantic STT sessions with Morse decoding |
| D | Native Morse TTS produces PCM, cancels and replaces without affecting other scopes. | Introduce semantic TTS sessions with Morse synthesis |
| B | A room uses scoped Morse STT; hosted STT remains usable through a private bridge. | Route room speech input through semantic sessions |
| C | Deepgram STT owns its wire protocol and local workers; remove the STT bridge. | Migrate Deepgram speech recognition to sessions |
| E | Room, opening and private TTS use scoped sessions and confirmed playback. | Route speech output through semantic sessions |
| F | Deepgram TTS preserves cancellation/accounting through the local boundary. | Migrate Deepgram synthesis to semantic operations |
| G | Contrasting provider profiles and a standalone scoped authoring guide pass. | Add speech provider conformance examples |
| H | Every speech consumer uses scoped execution; remove obsolete globals/config. | Complete speech session migration and remove legacy contracts |

## Checkpoint R — Restore scoped ownership and admission

Outcome: two isolated room-equivalent trees, and two sibling speech scopes in one tree,
remain independently usable while a provider stalls, fails or is cancelled. This checkpoint
uses controlled providers and the existing native Morse prototype; no room consumer migrates.
It owns the foundational allocation work previously left ambiguous in A2/A4.

- [x] **R1 — Red isolation and ownership.** Extend `test/vxpipe/call_engine/speech/startup_isolation_test.exs`
  and add `test/vxpipe/call_engine/speech/scope_lifecycle_test.exs`: include separate-room and same-room siblings, queued
  expiry/cancellation, owner loss before bind, stale stop after replacement, and subtree failure.
  Keep the exact-PCM readiness/turn proof; a quick `:starting` return alone cannot make it green.
- [x] **R2 — Explicit local scope.** Add a minimal `lib/speech/capability_tree.ex` and typed
  scope/allocation handle; revise `speech/session.ex`, `session_tree.ex` and `channel.ex`.
  Require the caller's owning scope for standalone use. Remove prototype global speech
  supervisor/registry entries from `application.ex`; no implicit global fallback. A local
  session supervisor and its workers belong to that scope. Retain existing legacy globals
  only for callers that have not migrated. Name each supervisor explicitly.
- [x] **R3 — Bounded two-phase start.** Reserve local admission, bind owner/attempt/generation,
  and create the startup/adoption deadline before queueing. Admit only lightweight trees;
  perform blocking credential/provider initialization asynchronously below them, preserving
  existing authorization boundaries. Return a starting handle, then allocation-bound readiness.
  Check owner/lease/expiry before allocation and adoption; reject cancelled queued work without
  creating a provider. Keep retained startup arguments opaque; retain private initialization
  until async handoff and remove it on handoff, cancellation or expiry, with status/crash tests.
- [x] **R4 — Exact teardown.** Implement handle-based close before and after provider creation.
  Provider/allocation-local worker loss retires that allocation; failed preparation preserves
  active STT. Shared capability-control/session-supervisor loss retires the whole capability
  tree; unrelated trees survive. Distinguish allocation close from capability stop, monitor
  descendants, reject late events and forbid silent restart/replay. Adoption changes authority,
  not parentage. Include admission and failed-start cleanup in the original startup budget;
  settle it after activation/adoption. Prove subsequent operations have independent deadlines
  and an active session survives beyond its startup deadline.
  Use explicit OTP child restart/shutdown/significance policies to enforce owned process
  lifetimes; retain application notifications and external owner/lease monitoring where needed.
- [x] **R5 — Runnable gate and review.** Exercise actual Morse recognition while sibling startup
  is held; inspect the owned tree and confirm prototype global session children are removed
  and each new allocation's execution stays in scope. Legacy globals serve only unmigrated
  callers. Re-run the STT burst benchmark and record distributions/known limits, without
  changing its baseline.
  Inject provider, control and local-supervisor failure independently. Record failure-to-safe
  notification/teardown and explicit replacement-to-ready timing while healthy peers continue;
  do not infer automatic recovery or recovered in-flight speech from a new allocation starting.
  Review with GPT-6 Astra xhigh and update the owning example, contract and labnotes.
- [x] **Exit R.** The existing startup regression and new ownership/cancellation cases are green,
  no speech allocation outlives its scope/lease, other scopes still reach ready/recognize PCM,
  allocation and capability failure boundaries pass independently, startup deadlines settle,
  old room tests and all five root gates pass. This accepts the first milestone implementation checkpoint.
  The separately user-authorized adoption-repair commit records its bounded verified slice;
  it does not satisfy this Exit gate or authorize room migration.

R implementation evidence: [deadlines and failure containment](../speech-deadlines-and-failure-containment.md).
The persistent input/admission worker adjustment was reviewed separately with GPT-6 Astra xhigh;
it closes R deadline requirements without accepting A4 or changing room migration order.

## Checkpoint A — Native Morse STT session

Prerequisite: R. Outcome: feed an independently generated PCM phrase into the scoped session
facade and receive ready/start/transcript/end events without a socket or JSON translation. Existing room speech
continues using its current path until B.

- [x] **A1 — Red contract test.** Add `test/vxpipe/call_engine/speech/stt_session_test.exs`:
  start under `start_supervised!`, inject the existing independent Morse fixture in odd-sized
  chunks, and expect one ordered final transcript. Confirm failure because the new API is absent.
- [x] **A2 — Finish the minimal STT contract.** Refine `lib/speech/stt_provider.ex`,
  `descriptor.ex`, `event.ex` and `session.ex` on R's owned allocation API. Pure public
  configuration, typed metadata and readiness stay separate from credential lookup and I/O.
  Providers receive local handles; no public transport interface or global supervisor choice.
- [x] **A3 — Native provider.** Add `lib/provider/morse_code_stt/session.ex` around the existing
  Morse Config/Decoder; publish semantic events directly. Retain old callers until B and avoid
  duplicating the decoder or creating fake hosted request IDs.
- [x] **A4 — Bounded persistent input.** R brings forward the minimal persistent local
  input worker because Task admission cannot bound the preceding wait. Complete its remaining
  input/usage contracts and performance acceptance here. Keep one admitted
  chunk, size/age bounds, synchronous acceptance evidence and an independent cancel/deadline
  path. Test held provider input, timeout, duplicate envelopes and late results without a
  control/worker callback cycle. Preserve usage when acceptance and decoding complete at
  different times; benchmark audio-call, first-text and turn-end distributions against baseline.
- [x] **A5 — Failure and example.** Cover malformed/oversized input, duplicate envelopes,
  teardown during startup, safe errors and no audio/text/secret inspection. Add a short runnable
  standalone example to `apps/vxpipe_call_engine/README.md` with truthful format limitations.
- [x] **Exit A.** Independent expected text is observed through the public session API; owner
  death produces monitored teardown; existing Morse codec/transport/room tests and root gates pass.

Revalidation gate: the R isolation/cancellation tests stay green after the native data path
changes. Preserve the historical failure and 68,400-turn report. A has no room migration;
D next proves TTS ownership, output credit and cancellation before B starts integration.

A implementation and load evidence: [native STT contract](../native-stt-contract.md).
All five root gates passed: 1,880 tests, zero failures, 40 excluded (seed 330044).
The independently reviewed source passed 123,996 final latency/fault/adoption turns.
The report preserves earlier failures, the nonrepeated tail spike and workload limits.

## Checkpoint D — Native Morse TTS session

Prerequisites: R and A; execute D before B. Outcome: a standalone scoped `speak` request
produces independently checked PCM; cancellation while delivery is backpressured remains responsive and a replacement request finishes cleanly.

- [ ] **D1 — Red streaming test.** Add `test/vxpipe/call_engine/speech/tts_session_test.exs` for
  native Morse speak, acknowledged bounded audio and one terminal completion. Assert sample
  runs with the existing independent fixture/decoder, not solely an encoder/decoder round trip.
- [ ] **D2 — TTS contract/output helper.** Add `lib/speech/tts_provider.ex`, `output.ex` and typed
  TTS request/event support. Define admission versus `input_submitted`; reuse A's descriptor,
  identity and bounded event delivery, with R's explicit local scope. Add local provider/output
  workers; do not introduce a global TTS supervisor, queue or per-frame Task factory.
- [ ] **D3 — Native provider.** Add `lib/provider/morse_code_tts/session.ex` using the existing
  incremental Encoder. Remove Speak/Flush/Interrupt JSON from this native path; retain the old
  room entry temporarily until E. Preserve sample pacing, output format and size limits.
- [ ] **D4 — Red cancellation races, then implement.** Hold audio credit, cancel before first
  audio and mid-output, race done/cancel, then synthesize again. Prove bounded memory, no stale
  audio, idempotent cancellation, one terminal result and prompt owner/producer teardown.
  A blocked TTS sink must not stop same-room STT or another scope's synthesis/cancellation.
- [ ] **D5 — Standalone demo.** Document one text-to-PCM/WAV example and its format/sample
  assumptions. Add an opt-in latency lane for first audio, generation completion and controlled
  sink-playout completion under load, separately from STT. Keep generated audio artifacts
  outside version control and retain safe volume.
- [ ] **Exit D.** A long phrase drains completely with one chunk in flight, the independently
  checked replacement is clean, and current room TTS remains usable with all relevant gates green.

## Checkpoint B — Room STT and policy integration

Prerequisites: R, A and D. Outcome: the ordinary Morse audio room uses the new STT session while Deepgram remains available
through one private migration bridge. Denying transcription demand prevents speech processing.

- [ ] **B1 — Red room test.** Extend `provider/morse_code/room_round_trip_test.exs` to select the
  native session with no transport registration, assert attributed text, and finish the response.
- [ ] **B2 — Resolve the session.** Update `lib/capability_catalog.ex`, STT branches in
  `plan_startup.ex`, `speech_to_text_runtime.ex` and owning startup/supervisor calls. Use the
  descriptor and existing credential source; add a private legacy-STT bridge only for Deepgram.
  Nest the STT capability/ingress and its workers under the connection's speech tree. Migrate
  speech lookup, stop, monitoring and readiness bindings together using exact allocation
  handles, preserving public room command results and unrelated direct-child capability APIs.
- [ ] **B3 — Preserve policy allocation.** Change `lib/capability/speech_to_text.ex` and its
  `state.ex`, `transport_connector.ex`, `policy_preparation.ex` and private-allocation integration
  to bind session events instead of wire messages. Replace the hard-coded global connection
  task supervisor with the local scope, including inside the Deepgram bridge. Prepared sessions
  already have their final room parent and stay fenced until explicit lease adoption.
  Remove connector owner/provider kill chains made unnecessary by the new parentage. Preserve
  readiness-before-event ordering and pending-policy lease monitoring; document any connector
  code temporarily retained for the Deepgram bridge and remove that bridge in C.
- [ ] **B4 — Red privacy races, then implement.** Test no-demand startup, revoke/relax, a delayed
  old transcript, immediate ready during connection, cancelled preparation and unrelated policy
  changes. Add connection/participant departure, same-room peer progress and stale-stop versus
  new-generation tests. Retain exact interval attribution and fresh readiness for replacements.
- [ ] **B5 — Usage/config/docs.** Preserve STT accepted-audio/final-text counting, provider IDs
  and payload-free telemetry. Update the Morse entry in root `config/dev.exs` and the room
  example. Keep hosted configuration working through the bridge.
- [ ] **Exit B.** Native Morse STT completes the real room loop; media-policy, readiness,
  barge-in, usage and redaction tests pass alongside the existing hosted adapter tests.
  The old startup coupling test also passes through real room composition and both bridge/native
  providers; no call-level latency conclusion is inferred only from standalone benchmarks.
  Re-run the paired scoped room workload with its exact-content/identity assertions and agreed
  latency budgets. Inject allocation and capability-tree loss through actual room composition;
  verify sibling progress, correct unavailability and no orphan or stale events.

## Checkpoint C — Native Deepgram STT

Prerequisite: B. Outcome: the same room capability accepts Deepgram recognition events through a native semantic
session. A tagged local wire server proves framing/authentication; live acceptance is separate.

- [ ] **C1 — Red wire boundary.** Extend the tagged `test/integration/speech_socket_privacy_test.exs`
  and STT capability fixtures to drive the semantic API, including a Connected frame coalesced
  with the upgrade, ordered turns and an upstream duplicate.
- [ ] **C2 — Move protocol ownership.** Add `lib/provider/deepgram/flux/session.ex`; retain or
  extract the existing bounded parser from `flux.ex`. Reuse `socket.ex`/`socket_connection.ex`
  internally using the allocation's local I/O ownership. Delayed upgrade/authentication must
  not block siblings. Translate to typed events and reject stale upstream sequence IDs.
- [ ] **C3 — Close/failure/readiness.** Prove provider acknowledgement is required, bad/stalled
  upgrades fail safely, owner loss closes allocation, privacy cancellation drops late results,
  and no reconnect occurs. Preserve supported linear16/Opus framing and existing timeouts.
- [ ] **C4 — Remove STT bridge.** Update Deepgram selection/config and test fixtures; remove the
  migration bridge and old STT transport requirements from engine startup. Private wire helpers
  may remain. Update the STT authoring example and usage/telemetry mapping.
- [ ] **Exit C.** Local wire, STT room/policy and credential boundary tests pass. Run the existing
  tagged live Flux/RTVI lane when its inputs are available; record missing credentials/audio or
  endpoint mismatches as hosted acceptance blockers, without claiming local fixtures prove parity.

## Checkpoint E — Room TTS, playback and independent opening

Prerequisites: D and C. Outcome: the real Morse audio round trip uses both new interfaces; independent opening TTS
works for an initial human receiver and remains gated on actual output playback.

- [ ] **E1 — Red playback test.** Extend `text_to_speech_turn_test.exs` and
  `opening_audio_room_test.exs`: select native Morse without a transport, withhold sink finish,
  and prove generation completion does not finish the turn or release opening input.
- [ ] **E2 — Resolve TTS sessions.** Update TTS branches of `plan_startup.ex`,
  `text_to_speech_runtime.ex`, `capability_catalog.ex` and capability-supervisor/startup callers.
  Compose descriptor metadata with existing selection and credential-scoped cache identity.
  Keep one private legacy-TTS bridge for Deepgram until F. Give conversation, independent
  opening and private preparation separate purpose/generation allocation handles. Update their
  stop/lookup/readiness paths with the new tree ownership; a participant-only lookup is unsafe.
- [ ] **E3 — Simplify capability orchestration.** Change `lib/capability/text_to_speech.ex` to
  call speak/cancel and handle request-scoped audio/terminal events. Keep its bounded queue,
  draining states and ledger. Use a persistent local output worker to replace per-chunk
  `Task.Supervisor.async_nolink` creation and its result/monitor/shutdown bookkeeping;
  keep output credit, failure acknowledgement and independently responsive interruption.
  Any retained per-chunk task path needs measured justification recorded in this checkpoint.
  Put provider speech IDs and wire offset translation in the bridge or native provider.
  The per-allocation playback ledger retains actual sink progress, including
  interruption after generation finishes. Preserve listener-first interruption and the normal
  unavailable path.
- [ ] **E4 — Preserve accounting and cache.** Red-test rejected admission, admitted-but-unsent
  failure, submitted-text failure, discarded generated audio, duplicate terminal settlement,
  cancellation during sink drain followed by correct next-request playback offsets,
  warm cache credential checks and independent opening/agent voices. Update capability Usage
  and `usage/text_to_speech_attempt.ex` only where event projection changes.
- [ ] **E5 — Consumer/config coverage.** Route private briefing, transfer preparation and source
  restoration through the same startup boundary. Update Morse host config/docs. Keep their
  existing authorization and private-output tests; do not rebuild these workflows. Use explicit
  opening/preparation leases, including human-entry rooms with no agent activation. Cache data
  may be shared, but synthesis/playback ownership stays local. Prepared trees keep their final
  parent and adoption cannot accidentally stop a concurrent conversation or opening.
  Exercise recipient permission revocation during output, private-recipient isolation and
  recording-policy changes on the new path; transcript-demand revocation alone is insufficient.
- [ ] **Exit E.** Two full room turns, interrupted replacement, cold/warm independent openings
  and human-entry opening gates pass. Recording privacy and usage remain unchanged; hosted TTS
  still works through its private bridge. Withhold one scope's output/connection and prove
  another room and another purpose in the same room stay usable; record room-level latency.
  Repeat failure-boundary and exact-cleanup tests for conversation, opening and private speech.
  Compare first audio, sink finish and confirmed playback separately with the recorded baseline.

## Checkpoint F — Native Deepgram TTS

Prerequisite: E. Outcome: hosted TTS implements semantic speak/cancel, and the capability has no knowledge of
Deepgram speak/flush commands, speech IDs or cumulative interruption offsets.

- [ ] **F1 — Red hosted mapping test.** Drive a native session through controlled protocol
  frames and tagged local wire tests. Cover accepted Speak followed by failed Flush, first
  audio without changing the engine API, and completion only after all audio is delivered.
- [ ] **F2 — Provider ownership.** Add `lib/provider/deepgram/flux_text_to_speech/session.ex`;
  reuse validated configuration/parsing and the private Mint socket implementation inside the
  allocation's local worker tree. Own wire
  speech correlation, flush, cumulative offsets and safe interruption/drain boundaries here.
- [ ] **F3 — Red isolation tests, then implement.** Test cancel before speech start, zero-played
  cancellation, late old audio, cancellation with an outstanding sink write, failed terminal
  isolation and provider disconnect. Keep one authoritative request mapping and bounded waits.
- [ ] **F4 — Remove TTS bridge.** Update catalog/host settings, integration fixtures and the
  tagged live TTS test to call semantic operations. Delete the bridge; retain useful internal
  socket/parser helpers. Verify credential/header/payload redaction in both success and failure.
- [ ] **Exit F.** Local wire tests, queued turns and long-response gateway egress tests pass.
  Run existing tagged live TTS and RTVI tests when available; record the actual endpoint/model
  and safe result. Missing live evidence leaves hosted acceptance open, not silently checked off.

## Checkpoint G — Authoring guide and contrasting contract profiles

Prerequisites: C and F. Outcome: a developer follows the guide to implement and run a provider using the public
behaviour/helpers, without depending on Call Engine private messages or any real new account.

- [ ] **G1 — Shared conformance harness.** Extract project-owned assertions from A/D into
  `test/support/speech_provider_contract.ex` (or cohesive separate STT/TTS files). Expose setup
  hooks and observable assertions, not assumptions about provider internals or OTP behavior.
  Require explicit owned scopes, isolation/deadline/queued-cancellation assertions and proof
  that a quick starting handle cannot substitute for provider readiness.
- [ ] **G2 — Request TTS profile.** Add a test-only provider whose owned worker returns streamed
  audio without connected/started wire messages; test bounded whole-response adaptation too.
  Prove cancellation/owner death terminate the worker and late completion cannot revive output.
- [ ] **G3 — Context and batch profiles.** Add controlled scenarios for context-tagged cancel
  and multiple/coalesced synthesis-batch boundaries. Prove a flush count or first batch `done`
  cannot finish the engine request. These model Cartesia/ElevenLabs/Rime distinctions, without
  purporting to be those providers' protocol implementations.
- [ ] **G4 — Segmented STT profile.** Test revised partials, committed segments, optional eager/
  resume and actual end-of-turn separately. Reject a manual-finalize/no-endpointing descriptor
  at conversational admission. Include a provider with no upstream sequence numbers and prove
  local envelope ordering without inventing upstream deduplication evidence.
- [ ] **G5 — Guide and runnable example.** Add `docs/speech-integration-guide.md` with a complete
  minimal provider, descriptor, private credential flow, registration location, event/error
  table, bounded delivery example and exact conformance commands. Exercise the example as code
  in test support. Update the Call Engine README and link the comparison's supported/deferred modes.
- [ ] **Exit G.** Both native providers and the independent structural profiles pass the shared
  checks; the guide requires neither a public transport module nor raw message tuples. Helpers
  do not assume WebSockets, vendor speech-start events or equal provider feature sets.

## Checkpoint H — Final configuration and all-consumer acceptance

Prerequisite: G. Outcome: source and embedded configurations run only the final contract, existing call specs
still load, and all remaining references are deliberate private wire implementations.

- [ ] **H1 — Finish config migration.** Remove obsolete public provider/transport settings and
  callback behaviours from `plan_startup.ex`, runtime structs, root `config/dev.exs`, test
  support and embedded examples. Remove `AudioOutputTaskSupervisor` and
  `SpeechToTextConnectionTaskSupervisor` application children after auditing/migrating their
  final speech callers; never add a replacement global speech executor. Keep host limits and
  closed catalog validation explicit.
  Obsolete settings fail clearly; do not silently ignore them or introduce persisted bridges.
- [ ] **H2 — Verify activation boundaries.** Run focused credential tests in Engine, Calls and
  Persistence for tenant override/platform inheritance, fresh lookup on new activation, retained
  snapshots in running sessions, opening cache scope, private briefing and source restoration.
  Stored Call Specs/plans keep their current schema and contain no private session data.
- [ ] **H3 — End-to-end acceptance.** Run the deterministic direct-PCM room demo, existing
  native WebRTC/egress regression tests and existing hosted STT/TTS lanes. Exercise typed and
  spoken interruption followed by another usable turn. Carrier-specific new live calls are not
  required for an unchanged transport boundary; affected carrier media regression tests remain.
- [ ] **H4 — Documentation and rendered check.** Update architecture, development, interruption,
  readiness, inline-selection and privacy docs to describe the implemented boundary. Inspect
  the existing sample call using `agent-browser`/Chrome for connected, speaking, interrupted and
  replacement states. Record any unavailable browser/provider check explicitly; source review
  cannot establish rendered or audible behavior.
- [ ] **H5 — Final audit/gates.** Search for legacy callbacks/tuples outside provider-private
  modules, inspect status/diffs, run all common root gates, and record actual results and unresolved
  external checks. Inspect actual speech ancestry and run the scoped isolation, paired burst
  and paced latency lanes for STT and TTS. Report each repeat, count and latency distribution;
  reproduced stability failures keep room migration pending its gates. No new hosted provider or format may
  appear merely because it was compared.
- [ ] **H6 — Demonstrate simplification.** Record removed modules/callbacks and lifetime/task
  bookkeeping against the pre-migration baseline, plus retained monitors and their domain
  responsibilities. Confirm B/E deletions and C/F bridge removal rather than counting moved
  code as eliminated complexity. Do not delete policy, lease, readiness-ordering, usage or
  playback logic simply because a supervisor now owns the worker. No arbitrary line-count
  target substitutes for passing the behavioral gates.
- [ ] **Exit H.** Complete the evidence ledger, all required acceptance lanes and author guide;
  mark the milestone/index complete together only then. Packaging and retention holds remain.

## Verification map and commands

Existing tests to retain/extend, not a claim that they ran during this planning task:

| Contract | Existing Engine tests under `test/vxpipe/call_engine/` unless noted |
| --- | --- |
| Scoped ownership/startup | `speech/{startup_isolation,scope_lifecycle}_test.exs`; existing owned-scope load baseline in `bench/speech_latency.exs` |
| Independent Morse audio | `provider/morse_code/{codec,local_transport,room_round_trip}_test.exs` |
| STT readiness, ordering, privacy | `capability/speech_to_text_test.exs`, `capability/speech_to_text_redaction_test.exs`, `speech_to_text_media_policy_room_test.exs`, `media_policy/speech_to_text_demand_test.exs` |
| TTS queue, credit, interruption, usage | `capability/text_to_speech_test.exs`, `text_to_speech_turn_test.exs`, `text_to_speech_runtime_test.exs`, `usage/text_to_speech_attempt_test.exs`, `spoken_barge_in_test.exs` |
| STT usage and readiness resources | `usage/speech_to_text_session_test.exs`, `readiness/provider_test.exs`, `media/connection_readiness_test.exs` |
| Opening/recording gate | `opening_audio_room_test.exs`, `opening_audio/asset_pipeline_test.exs`, `recording/egress_policy_readiness_test.exs` |
| Wire authentication and bounds | Engine `test/integration/speech_socket_privacy_test.exs`; synthetic local credentials only |
| Hosted interoperability | Engine `test/integration/deepgram_flux_text_to_speech_test.exs`; Gateway `test/integration/{rtvi_deepgram_flux,rtvi_deepgram_flux_text_to_speech,deepgram_flux_opus}_test.exs` |
| Credential selection/cache isolation | Persistence `test/vxpipe/persistence/{provider_credential_runtime,tenant_opening_audio,scoped_provider_credentials}_test.exs`, plus owning Engine/Calls credential tests |

From `apps/vxpipe_call_engine`, run the smallest affected file while iterating, for example:

```shell
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
mix test --include integration test/integration/speech_socket_privacy_test.exs
```

The second command uses local network fixtures and remains tagged/excluded from the default
suite. Run live files explicitly and individually from their owning child only when required
credentials/fixture audio are available. Do not enable every external integration test by
accident, print secrets, or substitute a local server for claimed hosted acceptance.

From the umbrella root at each completed code checkpoint:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix deps.unlock --check-unused
```

Use monitors and acknowledgements for race tests, no sleep/liveness polling. Preserve the
existing limits unless a focused red test and documented decision require changing one.

## Evidence ledger

Pre-approval experiment evidence is separate from the checkpoint ledger: 12,996 measured
turns and 12 loaded control scenarios passed through test-owned scopes. Full root acceptance
was not green: the original prototype startup test was red; a prepared WebRTC decoder
test also failed once and passed on focused reruns. No causal connection from this experiment
to that decoder failure was established. See the [experiment report](../scoped-speech-experiment.md)
for timing distributions, exact covered permissions and excluded production paths.

| Checkpoint | Implementation | Red/green and root evidence | External/manual evidence |
| --- | --- | --- | --- |
| R | Accepted: local scopes, persistent admission/input, bounded handoff and exact close | 70 speech cases and 770 Call Engine tests pass; all five root gates pass (1,868 tests, zero failures, 40 excluded; seed 892574); Astra reviewed | Latest evidence: 39,360 concurrent-fault turns, 68,400 unchanged legacy/native turns, 16,236 adoption-churn turns; historical reports retained |
| A | Accepted: validated native STT metadata/events and bounded input acceptance | 103 focused cases, including 82 speech cases, pass; all five root gates pass (1,880 tests, zero failures, 40 excluded; seed 330044); Astra reviewed | Verbatim example and final 123,996 latency/fault/adoption turns pass; earlier runs and tails retained |
| D | Not started | Pending | PCM playback/replacement pending |
| B | Not started | Pending | Real room loop pending |
| C | Not started | Pending | Local wire and hosted STT pending |
| E | Not started | Pending | Room/opening proof pending |
| F | Not started | Pending | Local wire and hosted TTS pending |
| G | Not started | Pending | Independent guide exercise pending |
| H | Not started | Pending | Browser/hosted final acceptance pending |

## Specification review

Local review on 2026-09-19 checked the proposed API against current source and the requested
provider documentation. It is separate from implementation and is not an independent-agent
approval. The review corrected four risks: segment finality was too easily confused with turn
end; synthesis batches with request completion; admission with provider submission for usage;
and local cancellation with upstream cancellation certainty. The design now states each boundary.

Revised dependency review: all direct prerequisite milestones precede this entry in the index.
R first replaces global ownership. A/D prove both native directions in isolation before B;
B/C migrate STT and remove its bridge, then E/F migrate TTS and remove its bridge. G tests
contrasting shapes; H removes legacy configuration and verifies all consumer ownership.
Order: R → A → D → B → C → E → F → G → H. Existing A-H IDs retain their meanings.
The conservative index position is before delivery and retention; no runtime dependency on
the onboarding UI is introduced and existing packaging authorization holds are unchanged.

Research and planning verification are recorded in the
[labnote](../../labnotes/20260919-1534-simplify-speech-integrations.md). No implementation task
or acceptance checkbox is checked by writing/reviewing this specification.

Implementation review is separate: GPT-6 Astra xhigh found startup/privacy/cleanup defects in
the initial prototype. Focused regressions cover those corrections; final acceptance remains
blocked by the independently reviewed [startup isolation evidence](../speech-startup-isolation.md).
See [implementation labnotes](../../labnotes/20260919-1559-semantic-morse-stt.md) and
[verification labnotes](../../labnotes/20260919-1624-speech-startup-isolation.md).

Replan review on 2026-09-19 is separate from implementation progress. The
[ownership proposal](../speech-session-ownership.md) closes the owner/lease/consumer, queued
cancellation, stale-stop, readiness, parentage, failure-domain, deadline-lifetime and
private-init-retention gaps found during GPT-6 Astra xhigh review.
See the [replan labnote](../../labnotes/20260919-1646-replan-speech-ownership.md). The new R
checkpoint and revised gates are specifications; the baseline is recorded before continuing R,
and none is accepted.

Post-experiment planning refresh on 2026-09-19 records the main/prototype distinction, measured
latency and capacity limits, explicit failure/cleanup evidence and concrete B/E/H code-removal
gates. Dependency order and checkpoint identities are unchanged; new wording does not approve
the migration or count test-only bridges as implemented slices. The separate review and
documentation verification are recorded in the
[refresh labnote](../../labnotes/20260919-1814-refresh-speech-milestone.md).

Implementation review for R (2026-09-19): GPT-6 Astra xhigh reviewed the local workers,
deadline/cancellation tickets, authority handoff, supervision boundaries, private-data handling,
red tests and fault-load methodology. The minimal persistent input worker moved from A4 into R
because Task admission itself was unbounded; this does not accept A4 or reorder migration.
The review's close/adoption race findings were reproduced with deterministic barriers and fixed.
Final source review found no remaining R blocker, conditional on root gates and accurate evidence.

R acceptance: all five root gates passed on the reviewed source, with 1,868 tests, zero
failures and 40 exclusions (seed 892574). The 70 speech cases and three latest load diagnostics
passed. At R acceptance, A4 remained open for its broader input/usage/envelope contract;
A and D remained prerequisites to room migration. No production capacity or overall speedup was claimed.

A implementation review and acceptance (2026-09-19): GPT-6 Astra xhigh reviewed descriptor
validation, event evidence, bounded busy rejection, usage boundaries and stale work. Its
eager-end consistency finding was reproduced red and fixed. The first root run exposed a
test's overly specific safe-failure category; a focused rerun exposed an implicit 100 ms
notification wait. Reviewed test corrections preserve actual deadline/isolation assertions.
The complete root rerun passed with seed 330044: 1,880 tests, zero failures, 40 excluded.
Final serial load diagnostics passed 123,996 measured turns. R and A are accepted (2/9);
D is next. The user's reliability priority accepts small processing overhead without waiving
failure, delivery, privacy or cleanup gates. Room migration remains pending.
