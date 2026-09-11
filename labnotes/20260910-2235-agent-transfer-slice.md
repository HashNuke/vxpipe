# Agent transfer slice

## 2026-09-10 — baseline and first checkpoint

- Started from clean `main` at `db5e06e` on `milestone/agent-transfers` after the opening-audio
  milestone was committed and pushed.
- The approved slice transfers conversational responsibility between allowlisted agent
  participants. Room Authority must retain control until the destination activation is ready and
  the room commits; failed preparation leaves the source responsible.
- Existing definition parsing deliberately rejects every non-empty `transfers` list, while
  `transfer` is already a reserved authored tool alias. `PlanStartup` independently rejects plans
  containing transfer refs. No runtime transfer action or room transition exists yet.
- The first checkpoint will establish only the authoring/compilation boundary: validate unique
  definition-local agent targets, derive one default-blocking transfer binding for a non-empty
  allowlist, expose only target refs and safe descriptions to the model, and keep an empty list free
  of that tool. Runtime invocation and room prepare/commit remain later red-green checkpoints.
- Tool execution semantics remain unchanged: both blocking and non-blocking tools always run in
  independently supervised activation-owned workers. The generated transfer binding defaults to
  blocking later caller turns; this is conversation admission, never inline execution.

## 2026-09-10 — authoring and compiler boundary

- Wrote the focused transfer definition/compiler test first. It failed at compilation because no
  participant-transfer binding existed, then passed after the smallest parser, resolver, and
  descriptor implementation.
- Participant parsing now accepts an ordered list of unique identifier refs. Definition validation
  rejects malformed, duplicate, missing, self, and human destinations with the exact list index;
  this milestone intentionally supports only agent destinations.
- Compilation performs a second pass after every runtime participant identity exists. A non-empty
  list derives one private `transfer` binding containing the immutable source identity and target
  identity map. The model-visible descriptor contains only the destination refs and safe authored
  descriptions. Empty lists add no tool, and authored use of the reserved alias remains rejected.
- Added a separate red/green check for participant-local tool visibility. A generated transfer tool
  now accepts the same hidden/metadata/full override as other configured tools.
- Released schema `20260910.04` rather than changing accepted `20260910.03` behavior in place.
  Current fixtures and sample configuration now use the new version. The engine README states that
  live startup remains unsupported at this checkpoint.
- Runtime safety remains fail-closed: `PlanStartup` still rejects every plan containing transfer
  refs. No destination process, invocation execution, or room mutation was added.
- Focused transfer tests passed 4 tests, the existing compiler/descriptor/startup group passed 18,
  and the complete Call Engine suite passed 263 tests with 1 integration exclusion. Calls, Gateway,
  and Console passed 36, 66, and 57 tests respectively.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks
  passed. Umbrella tests remain blocked at Persistence database creation because this shell has no
  PostgreSQL password; no credential value was inspected or logged.

## 2026-09-10 — first runnable room transfer

- Added the end-to-end room test before runtime support. It failed at `start_call/2` with the
  expected `unsupported_call_plan` transfer rejection.
- Added a narrow participant-preparation value and split prepare/commit/discard operations from
  participant lifecycle admission. Prepared destination processes are not added to authoritative
  room state or archival history until commit.
- Room Authority retains a redacted transfer-runtime value containing the pinned plan and runtime
  settings needed to materialize a later agent. Runtime settings can include provider secrets, so
  their `Inspect` implementation exposes no fields.
- A transfer invocation still runs in the activation-owned supervised invocation worker. The worker
  resolves its private binding into a bounded request; Room Authority independently checks the
  room/incarnation, attached caller, current source participant/activation/coordinator, immutable
  allowlist, and destination participant identity.
- Successful preparation starts the destination participant, Agent Runtime graph, and selected TTS
  before swapping the active text/TTS routing. The same room and Call Variables process survive.
  Room Authority emits one `ToolCallCompleted` only after commit, using the existing client
  visibility path rather than adding an RTVI message, and the resulting private platform effect
  tears down the source participant subtree.
- Clearing the old room turn at commit prevents a later caller turn from being misattributed as an
  interruption of the destination. Late source output is rejected by the existing current-text-
  capability checks.
- A second focused test forges a stale source activation at the room boundary and confirms it is
  rejected before the destination activation or participant starts.
- The two focused transfer-room tests passed. The complete Call Engine suite passed 265 tests with
  one tagged integration exclusion. Calls, Gateway, and Console passed 36, 66, and 57 tests;
  Gateway retained four tagged exclusions. Root format checking, warnings-as-errors compilation,
  strict Credo, and unused-dependency checks passed.
- The umbrella test command was attempted again and remained blocked at Persistence database
  creation because the shell has no PostgreSQL password. No credential content was inspected or
  logged.
- This checkpoint implements fresh destination history only. Total deadline handling, controlled
  preparation failure/restoration, late completion exclusion, re-entry identity/activation rules,
  and alternate approved history projections remain pending.

## 2026-09-10 — total-attempt policy schema

- Released schema `20260910.05` with the closed call-level
  `transfer_policy.attempt_timeout_ms`. Omission selects 30 seconds; accepted authored values are
  bounded from 1 to 120 seconds and are pinned in `ResolvedCallPlan`.
- Transfer-capable activations set their supervised invocation timeout to at least the call's total
  transfer budget plus one second. This prevents the general 30-second worker default from racing a
  longer valid transfer policy; it does not add an inline or second execution path.
- The policy/compiler/startup group passes six focused tests. Runtime enforcement, failure cleanup,
  and late-result exclusion remain the next red-green checkpoint.

## 2026-09-10 — failed and expired destination preparation

- Added the controlled destination-failure room test before changing failure behavior. It confirms
  an invalid destination runtime returns the existing generic `tool_failed` event, leaves the source
  activation responsible, registers no destination participant, and routes the next caller turn to
  the source.
- Added the total-deadline room test next. Its initial run failed after two seconds because the
  destination provider blocked inside Room Authority and no attempt timer existed. The green test
  configures a two-second policy, blocks destination runtime construction, confirms the room still
  serves the source activation's deterministic blocking response, observes generic failure, releases
  stale setup, and confirms it cannot emit completion or replace the source.
- Added one explicitly named task supervisor per room incarnation. It owns only transfer preparation;
  participant and capability children still start through their existing owning dynamic supervisors.
  The preparation task builds the destination runtime, participant subtree, and selected TTS while
  Room Authority continues processing room messages.
- Room Authority owns the single pending attempt, deferred worker reply, monotonic deadline, and
  final source/target reauthorization. A concurrent attempt is rejected. Failure, task death, expiry,
  or lost authority removes the destination participant and TTS without changing source ownership.
  Clearing pending authority before the tool reply makes a late task result cleanup-only.
- Prepared TTS is named by room incarnation and participant for exact cleanup. Monitoring is attached
  by Room Authority only when that prepared capability commits, rather than leaving a monitor owned
  by the short-lived preparation task.
- Split destination preparation, authorization, cleanup, commit projection, pending data, and task
  supervision into responsibility-specific modules. `AgentTransfer` now coordinates their state
  transitions instead of accumulating provider startup, authorization, resource cleanup, and event
  construction in one module.
- A complete focused room run exposed a teardown-observation race in its assertion: the monitored
  source activation could exit just before its parent participant unregisters. The test now uses the
  room's own snapshot request as the processing acknowledgement before asserting participant absence;
  production teardown behavior did not change.
- The four focused transfer-room tests and complete 269-test Call Engine suite pass, with one tagged
  integration exclusion. Calls and Gateway pass 36 and 66 tests respectively; Gateway retains four
  tagged exclusions. Root formatting, warnings-as-errors compilation, strict Credo, and unused-
  dependency checks pass. The umbrella test command remains blocked at Persistence database creation
  because this shell has no PostgreSQL password; no credential content was inspected or logged.
  Alternate history projections, re-entry, private transfer history, and any applicable source-
  capability restoration evidence remain pending.

## 2026-09-10 — destination history policy schema

- Added the definition/compiler test first. It failed because agent participants had no inbound
  history policy and rejected `transfer_history` as an unknown field.
- Chose destination ownership so a source keeps the approved simple `transfers: [participant refs]`
  allowlist and cannot decide how much private history another agent receives.
- Released schema `20260910.06`. Every agent defaults to `%{mode: :fresh, turns: nil}`. The closed
  authored modes are `fresh`, `all_spoken`, `last_n_spoken`, and `selected`; only
  `last_n_spoken` accepts and requires a positive `turns` value.
- The compiler copies the validated policy into the immutable resolved destination participant.
  Human participants still reject the field through their existing type-specific field boundary.
- The eight focused transfer compiler tests and complete 271-test Call Engine suite pass, with one
  tagged integration exclusion. This checkpoint pins policy only; it does not yet seed destination
  model history or claim privacy projection at runtime.

## 2026-09-10 — vetted Agent Runtime history seed

- Added the Session test first. The positive case failed with `invalid_configuration` because the
  runtime had no initial-message option.
- Agent Runtime can now build a session conversation from its own system instructions followed by
  internal initial messages. The validator accepts only non-empty, bounded plain caller-user and
  tool-free assistant messages.
- It rejects replacement system instructions, engine-origin messages, tool messages, assistant
  tool calls, and tool-correlation metadata. This gives Call Engine a narrow privacy boundary rather
  than relying only on the future room projector to behave correctly.
- Seeded messages are committed history and are never accepted from the browser/client protocol.
  Call Engine does not yet supply the option, so this checkpoint alone does not change a transfer.
- The focused Session file passes seven tests; the complete Agent Runtime suite passes 53 tests with
  two tagged integration exclusions.

## 2026-09-10 — room-confirmed transfer history projection

- Added a pure projection test first; it failed because no room spoken-history value existed. The
  green implementation owns an insertion-ordered private queue whose inspection surface reveals
  only its size. `fresh`/`selected` return no messages, `all_spoken` returns all entries, and
  `last_n_spoken` returns the configured trailing utterance count.
- Added a room-level `all_spoken` test before integration. It failed because the destination request
  contained only its prompt and current caller message.
- Room input now records text only after the active agent accepts it; final STT records through the
  same accepted `SendText` path. Assistant output is recorded only from completed playout, at the
  same point where delivered output becomes an archive fact. Merely generated text is excluded.
- Transfer acceptance snapshots the destination-owned policy projection once, before the room-owned
  preparation worker starts. The worker passes only those vetted messages through PlanStartup and
  the activation graph to Agent Runtime. The destination still receives its own system prompt first.
- The room test sends two caller turns and one generated but unplayed assistant answer before
  transfer. Billing receives both caller messages in order and not the unplayed output.
- The six focused transfer-room tests plus the pure projection test pass. The complete Call Engine
  suite passes 273 tests with one tagged integration exclusion. Selected-mode reason/variables and
  re-entry remain pending.
- Calls and Gateway pass 36 and 66 tests respectively; Gateway retains four tagged exclusions. Root
  format checking, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  The umbrella test command remains blocked at Persistence database creation because this shell has
  no PostgreSQL password; no credential content was inspected or logged.

## 2026-09-11 — selected transfer reason boundary

- Added the selected-destination compiler test first. It failed because the generated transfer
  descriptor accepted only `destination` and could not require a reason for one history policy.
- The compiler now marks each private target with whether its pinned destination history policy
  requires a reason. If any target is selected, the generated JSON Schema uses closed per-target
  variants: selected destinations require `destination` and `reason`, while ordinary destinations
  continue to accept `destination` only.
- The private transfer request validates the same distinction independently of model-schema
  validation. Selected reasons must be non-blank and at most 1,024 characters; accepted text is
  trimmed and retained outside the request's inspection projection. Missing, blank, oversized,
  extra, or reason-on-ordinary input is rejected.
- This is an input-and-authority checkpoint only. The reason is not yet inserted into destination
  model context, and the destination-readable Call Variables projection remains pending with it.
- The combined compiler/room transfer run passes 15 tests. The complete Call Engine suite passes
  275 tests with one tagged integration exclusion.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Umbrella `mix test` still stops before test execution at Persistence database creation because
  the shell has no PostgreSQL password; no credential source was inspected.

## 2026-09-11 — transient Agent Runtime model context

- Added a Session test first. It failed because Session configuration rejected a model-context
  source and `ModelRequest` had no transient context value.
- Added a narrow `ModelContextSource` behavior and a fetcher separate from pending-tool context.
  The fetch occurs in bounded request work before every provider generation, accepts only a JSON
  object with string keys, enforces a configurable encoded-byte limit, rejects the runtime-reserved
  pending-invocation key, and terminates a stalled source task at timeout.
- `ModelRequest` carries the fresh object separately from committed messages. The ReqLLM adapter
  combines it with the independently validated pending projection inside the existing fixed
  trusted-state envelope. A second Session request sees a replacement value and no copy of the
  earlier value in conversation history.
- This provider-neutral checkpoint deliberately has no Call Engine or Call Variables dependency.
  The next checkpoint must provide the destination's permission-filtered variables plus selected
  reason through this source.
- The 16 focused source, Session, and ReqLLM projection tests pass. They include safe failure before
  provider generation when a configured source is unavailable. The complete Agent Runtime suite
  passes 58 tests with two tagged integration exclusions.
- The unchanged complete Call Engine suite passes 275 tests with one tagged integration exclusion.
  Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Umbrella `mix test` stops before test execution at Persistence database creation because the
  shell has no PostgreSQL password; no credential source was inspected.

## 2026-09-11 — destination model context

- Added the selected transfer room test first. It failed with an empty destination model context,
  establishing that schema capture alone had not delivered the reason or variables.
- Added one cohesive Call Engine `ModelContextSource`. Its redacted value retains only the already
  scoped Call Variables binding and optional transfer reason. It obtains a fresh projection through
  that binding for every Agent Runtime generation, so the variables owner—not Room Authority or
  Agent Runtime—continues to enforce participant identity and readable sections.
- Destination preparation passes the selected request reason into Plan Startup. Runtime graph
  construction installs the source without putting the reason directly in child options or model
  messages. The source emits `call_variables` and an optional `transfer.reason`; Agent Runtime owns
  only generic bounded JSON transport.
- The selected room fixture declares one billing-readable order section and one reception-only
  section. Billing receives the order value/revision plus the reason, no reception-only value, and
  no earlier caller messages. `Inspect` of the model request does not reveal the reason.
- Extended the existing variable-tool runtime check to prove the first generation sees the initial
  authorized projection and the private completion generation sees the updated value/global and
  section revisions. This restores the completed per-generation projection contract on the current
  ReqLLM runtime path.
- Call Engine Agent Runtime settings now expose a one-second source timeout and 256 KiB complete
  encoded model-context limit. The Call Variables call uses the same bounded timeout/deadline.
- The 25 focused transfer/definition-driven room tests pass. The complete Call Engine suite passes
  276 tests with one tagged integration exclusion. The complete Agent Runtime suite remains green
  at 58 tests with two tagged integration exclusions.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Umbrella `mix test` again stops before test execution at Persistence database creation because
  the shell has no PostgreSQL password; no credential source was inspected.

## 2026-09-11 — re-entry identity and activation authority

- Added the two-hop room test first. After reception transferred to billing and billing transferred
  back, it failed because the plan's original reception activation ID was reused.
- Room state now remembers which agent participant IDs have committed at least one activation. The
  set is incarnation-local and survives participant teardown; active participant membership remains
  a separate set.
- A first activation continues using the immutable plan's compiled activation. A re-entry keeps the
  same participant ID but materializes a fresh activation ID before asynchronous destination
  preparation. A narrow `DestinationParticipant` module also rebinds the generated transfer tool's
  private source activation; other tool bindings are unchanged.
- Transfer authorization still requires the current room text capability, participant ID,
  activation ID, coordinator PID, attached caller, stable plan participant, and allowlist. It no
  longer compares a re-entering activation with the plan's first activation ID.
- The test waits for each exact source participant supervisor to terminate and uses the room snapshot
  call as the teardown-processing acknowledgement before reversing direction. This removed a real
  test race without production polling or sleeps.
- The green flow proves reception's stable participant ID, absent original activation, fresh live
  session, destination-owned one-utterance spoken-history projection, and a successful subsequent
  transfer from its rebound private tool authority.
- Diff review found that the archive recorder still mapped the participant to the activation ID
  compiled in the immutable plan. A new red archive assertion timed out waiting for the fresh ID.
  Participant preparation now carries its activation ID, and commit rebinds the recorder before it
  emits the join fact. The green test observes the re-entry join under the fresh activation; later
  facts for that participant use the same binding. The focused file passes eight tests.
- Transfer-time first-message activation and explicit no-replay behavior remain pending; this
  checkpoint does not claim the combined re-entry acceptance item complete.
- The complete Call Engine suite passes 277 tests with one tagged integration exclusion. Umbrella
  formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Umbrella `mix test` stops before database-backed test execution because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.

## 2026-09-11 — transfer first-message and re-entry no-replay

- Extended the re-entry room test before implementation by configuring billing with a fixed first
  message. It timed out because transferred participants never applied their first-message policy.
- Transfer preparation now retains the room-authoritative first-activation decision. Failed
  preparation does not consume that decision because the participant is remembered only when its
  preparation commits.
- `FirstMessage` now builds activation-specific state for any resolved agent participant. The first
  committed activation keeps the authored wait/fixed/generated policy; subsequent activations use a
  completed no-replay state while retaining the entry caller as the idle/conversation target.
- Commit installs the destination text/TTS routes before starting its first message, so destination
  output cannot be admitted before control commit. The source remains scheduled for normal
  post-result subtree teardown.
- The green room flow observes billing's fixed greeting after its first transfer, transfers away,
  re-enters billing, and observes no repeated greeting. This completes the combined re-entry
  acceptance scenario together with the preceding identity, activation, history, rebound-authority,
  and archive assertions. The focused transfer-room file passes eight tests.
- The complete Call Engine suite remains green at 277 tests with one tagged integration exclusion.
  Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Root `mix test` again stops before database-backed test execution because this shell lacks the
  PostgreSQL SCRAM password; no credential source was inspected.

## 2026-09-11 — private transfer history and safe client failure

- Added the room and Gateway tests first. The transfer-room file failed twice while waiting for
  missing private `participant_transfer_started` facts. The Gateway projection test failed because
  full visibility encoded the synthetic internal `destination_participant_unavailable` atom.
- Room Authority now records a private start fact only after it authorizes the current source and
  accepts the transfer attempt. Successful commit and every terminal preparation path record one
  corresponding completed or failed fact. These facts carry the source participant/activation,
  caller, command/correlation/tool-call IDs, and pinned source/destination definition and
  participant identities.
- A dedicated `AgentTransfer.History` module owns the private transfer fact schema. Archive Recorder
  only supplies its generic internal-fact boundary; public event publication and RTVI do not learn
  the private schema.
- Destination preparation now reports a closed internal failure category for plan construction,
  participant startup, or TTS startup. Room-owned paths add deadline, preparation-supervisor,
  preparation-process, and changed-source-authority categories. Unknown values collapse to the
  closed process-failure category rather than archiving arbitrary provider terms.
- Model/agent behavior remains deliberately generic: the platform tool still returns
  `tool_failed`. Gateway now also forces a failed tool named `transfer` to that generic result under
  full visibility, preventing a future detailed internal atom from reaching the sample/debug UI.
  Other tools retain their existing configured full-error projection.
- Green evidence covers successful transfer history, destination-plan failure history, and a
  distinct total-deadline failure cause in the eight-test Call Engine transfer file. The focused
  Gateway projection file passes four tests. Cross-application review then found the Calls-owned
  closed fact vocabulary rejected the new kinds. A new focused projection test failed with
  `invalid_call_fact`; adding the three private kinds made it green and the complete Calls suite
  passes 37 tests. The complete Call Engine suite passes 277 tests with one tagged integration
  exclusion; Gateway passes 67 tests with four exclusions. Root formatting, warnings-as-errors
  compilation, strict Credo, and unused-dependency checks pass. Root `mix test` reaches the
  unchanged Persistence setup failure because PostgreSQL SCRAM authentication has no password in
  this shell; no credential source was inspected. No restoration mechanism is claimed by this
  checkpoint because agent-to-agent preparation has not stopped the still-working source.

## 2026-09-11 — bounded source TTS restoration

- Added the focused room test before implementation. It disconnected the source TTS transport while
  a destination model preparation was deliberately blocked, then released that preparation into a
  definite failure. The test failed waiting for a replacement transport: the room archived and
  returned the transfer failure immediately.
- Room state now retains the current agent's resolved TTS runtime separately from the temporary
  capability. Initial startup installs it, and successful transfer commit replaces it with the
  destination's pinned runtime. Provider credentials remain inside the existing redacted runtime
  structures and are not added to events or inspection output.
- A dedicated `SourceRestorer` owns eligibility and one fixed 750 ms restoration budget. The bound
  fits inside the transfer invocation's existing one-second envelope beyond the authored attempt
  deadline, so recovery cannot introduce a second open-ended phase. Restoration is permitted only
  while the original source activation and caller connection remain authoritative,
  source TTS is absent, and that source has a resolved TTS runtime. It starts through the existing
  room transfer `Task.Supervisor`; no provider or capability startup runs in a Room Authority
  callback.
- Preparation failure, process death, or total-deadline expiry either skips restoration when it is
  unnecessary or replaces the pending preparation with exactly one restoration task. Success
  activates a fresh monitor before replying to the original tool worker. Error, task death, or
  restoration expiry cleans any partial source TTS and terminates without retry. Late prepared TTS
  is discarded instead of acquiring room authority.
- Private failed-transfer history now records the closed restoration outcome `not_required`,
  `completed`, `failed`, or `timed_out`. The model/client still receives only `tool_failed`, including
  the successful-restoration scenario.
- The green test observes one replacement TTS transport and `restoration: completed`, then disconnects
  that replacement and proves no third start occurs. Existing ordinary failure/deadline checks record
  `not_required`. The complete nine-test transfer-room file passes.
- Diff review found that retaining the runtime made arbitrary provider/transport values available to
  Room Authority crash-state inspection. A focused test first failed by exposing a credential
  sentinel. `TextToSpeechRuntime` now exposes only its bounded request count and non-secret asset
  cache identity through `Inspect`; the provider and transport configuration stay private.
- The complete Call Engine suite passes 279 tests with one tagged integration exclusion. Root
  formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Root `mix test` stops at the unchanged Persistence database-creation failure because PostgreSQL
  SCRAM authentication needs a password absent from this shell; no credential source was inspected.

## 2026-09-11 — non-blocking transfer timeout cleanup

- The restoration deadline originally terminated its preparation task and then synchronously asked
  the room capability supervisor to remove any partial TTS child. A transport can still be inside a
  bounded `start_link` connection attempt at that point; its DynamicSupervisor is consequently busy
  completing `start_child`, so the cleanup call could block Room Authority beyond the restoration
  deadline.
- Added a controlled transport-start gate to the existing test transport and wrote the room race
  first. Initial source TTS starts normally, the replacement transport blocks during startup, and
  destination preparation has already failed. After the 750 ms restoration budget the test's
  bounded snapshot request failed to receive a reply, reproducing the Room Authority stall.
- `RoomTransferSupervisor` now starts fire-and-forget cleanup children for expired preparation and
  restoration tasks. These workers terminate the exact task and clean its destination or source TTS
  outside Room Authority. The supervisor limits all preparation, restoration, and cleanup children
  to four per room; saturation returns unavailability instead of allowing unbounded abandoned work.
- The green test receives a room snapshot within 250 ms after the restoration deadline, observes the
  generic transfer failure plus private `restoration: timed_out`, releases the late transport, and
  proves cleanup terminates it without installing it as the room capability. The focused ten-test
  transfer-room file and complete 280-test Call Engine suite pass. Root formatting,
  warnings-as-errors compilation, strict Credo, and unused-dependency checks pass. Root `mix test`
  stops at the unchanged Persistence database-creation failure because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.

## 2026-09-11 — failed destination commit race

- The remaining failed-commit acceptance boundary was not directly covered. Destination startup
  returned a preparation containing a participant supervisor, but `ParticipantLifecycle.commit/2`
  unconditionally added it to room state. If that supervisor exited before Room Authority handled
  the task result, the room could archive and publish a successful transfer to an unavailable
  destination.
- Added the deterministic integration test first. It blocks destination model setup, suspends Room
  Authority, releases setup until the preparation task exits normally, terminates the exact
  destination participant, and resumes Room Authority. The red run archived
  `participant_transfer_completed` and emitted `ToolCallCompleted`, reproducing the false commit.
- `ParticipantSupervisor.registered?/4` now owns the exact registry-identity query.
  `ParticipantLifecycle.commit/2` monitors the prepared participant and verifies that the same PID
  remains registered for its pinned tenant, room, and participant identity before admitting it to
  authoritative state. Missing or replaced membership returns `participant_unavailable` and
  removes the unused monitor.
- The transfer committer propagates that result without partial room mutation. Room Authority
  discards the dead preparation, leaves the source activation available, returns only generic
  `tool_failed`, and archives `destination_commit_unavailable` privately. The focused test passes;
  the combined transfer/participant-supervision group passes 13 tests, and the complete Call Engine
  suite passes 281 tests with one tagged integration exclusion. Root formatting,
  warnings-as-errors compilation, strict Credo, and unused-dependency checks pass. Root `mix test`
  stops at the unchanged Persistence setup failure because PostgreSQL SCRAM authentication needs a
  password absent from this shell; no credential source was inspected.

## 2026-09-11 — automated transfer acceptance consolidation

- Audited each unchecked acceptance clause against its owning boundary instead of treating prior
  prose as proof. Added direct assertions for authored `transfer` alias rejection, wrong source
  participant rejection, room/incarnation and entry-ref preservation, stable Call Variables
  ownership, complete source-subtree shutdown, and suppression of a forged late source text event.
- Strengthened the controlled deadline flow with a fixed destination greeting. While preparation is
  blocked, the source participant emits the deterministic default-blocking hold; after expiry and
  late preparation release, neither the destination greeting nor a completion event appears.
- Existing focused evidence covers injected targets, duplicate preparation, all four history modes,
  destination-readable selected variables/reason, generated-but-unplayed exclusion, and rejection
  of system/tool-bearing Agent Runtime seeds. The focused transfer/compiler/history group passes 22
  tests, and the focused Agent Runtime seed test passes.
- Reworded the older “source can converse” acceptance clause to match the later approved tool
  execution contract. The source retains responsibility throughout preparation, but the generated
  transfer tool is default-blocking, so later caller turns receive the platform hold without
  entering either agent's LLM. This changes no runtime behavior.
- All automated acceptance boxes are now evidence-backed. Manual rendered verification and the
  common milestone completion gates remain open, so the milestone itself is still partial. The
  complete Call Engine suite passes 282 tests with one tagged integration exclusion. Root
  formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks pass.
  Root `mix test` stops at the unchanged Persistence setup failure because PostgreSQL SCRAM
  authentication needs a password absent from this shell; no credential source was inspected.
