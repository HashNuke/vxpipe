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
