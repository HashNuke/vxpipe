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
