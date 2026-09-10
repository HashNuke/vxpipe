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
