# STS caller publication

## Baseline and reproduction

Previous checkpoint `208290da` synchronized the provider contract. The worktree
was clean; all five gates for runtime checkpoint `3b1fa264` had passed (2,205
tests, zero failures). Work directly under the user's later instruction.

Expanded the existing milestone caller-publication task before implementation.
Strengthened the real embedded transcript-mode matrix to require correlated,
room-owned caller start/text/end IDs and no duplicate pair. The initial run
fails in exactly the two modes without human STT: five tests, two failures,
both missing `ParticipantTurnStarted`. The human-STT modes and delayed-onset
case pass. This reproduces the externally visible missing publication, not a
test fixture or timeout problem.

## Design/dependency review

Keep immediate interruption in the capability. Publish a separate acknowledged
caller-evidence envelope carrying channel sequence, exact source, input epoch
and captured source policy intervals. The room owns public IDs and rechecks
current source, held state and policy before publication. Human STT continues
owning its existing caller pair when selected; this does not choose the STS
response controller or mirror text into a second response.

Bound unfinished caller associations to 16, separately from reply/output
queues. Preserve a turn until both semantic end and final text settle, allowing
late final text without creating a new turn. Retire owner-message sequences
with a scalar watermark; do not keep an unbounded public retirement history.
Exact raw provider references remain private map keys, avoiding collisions
between references and their stringified forms. Overflow fails the allocation.

Room release supplies a fresh input epoch; hold clears publication associations
and invalidates that epoch. This fences already-forwarded old owner messages
after release. Provider-level late events that first arrive after a hold/release
still require C's separate session/turn isolation work; do not label this as
complete hold or transfer acceptance. Tools and agent-output retirement remain
separate existing tasks.

## Implementation and follow-up regressions

- Added separate capability `CallerEvents` and room `CallerTurns` responsibilities.
  The former preserves acknowledged channel evidence and onset policy/epoch;
  the latter owns public IDs, publication and bounded association retirement.
  Removed the old unqualified caller-transcript publication path and the growing
  capability finalized-input set. Existing owner-message tests use the new
  evidence envelope; explicit input text still forwards evidence but cannot
  invent an audio turn without onset.
- Seven initial room-boundary cases first failed because the new boundary did
  not yet exist. The behavioral red evidence remains the real-room matrix.
  Reference/binary privacy, late final text, raw-key distinction, wrong
  capability/source, held/stale epochs/policies, human-STT exclusion, overflow,
  replacement and 100 settled turns now pass. Unrelated policy revisions retain
  source-specific intervals and do not discard valid caller text.
- Follow-up denial checks reproduced two defects in the new path: end-event
  fallback text bypassed caller transcript denial, and denied final text left
  completed capability associations pending. Both repairs preserve public audio
  completion without text and release the denied-text slot (12 tests, two
  failures before repair). Twenty denied-text turns retain no completed state.
- A corrected real-session regression proved overflow was reported only as
  `:provider_failed`; it now reports `:pending_caller_overflow` and monitors
  capability, provider and tree termination. The initial fixture used binary
  references rejected by the semantic channel; that fixture error was corrected
  to real references before counting the behavioral red result.
- A real-room regression proved repeated input-open calls changed the epoch
  while already open. Room release is now idempotent until hold invalidates it.
  The overflow and epoch cases failed together (29 tests, two failures), then
  passed. The generic Agent hold/release fixture was replaced with a supervised
  real STS capability: both sides' held state and shared epoch are asserted.
  No timeout was enlarged or introduced.

## Verification and handoff

The broadened child suite passes **146 tests, zero failures**, seed 0: selection,
examples, activation, ingress, room calls/publication/identity/transcript modes,
capabilities, independent-provider conformance, tools, output/turn control,
Morse conversation and the existing allocation-concurrency check. That existing
concurrency check is not the final ten-real-call comparative load requirement.

The provider contract now includes the implemented caller publication rules and
their limits, alongside its dedicated STS lifecycle section. Updated the author
guide, milestone and unchecked index entry together. The focused decision is
`docs/sts-caller-publication.md`; it records alternatives and separates owner
message retirement from still-unproven late upstream isolation.

Review and commit this coherent checkpoint before running all five umbrella
gates. Root verification is pending, not inferred from the previous runtime
checkpoint. Tool identity, agent-output retirement, external/hybrid room control,
full native/hold/transfer acceptance, hosted Google authorization, final load,
rendered UI and the remaining milestone gates stay open.

Documentation checks: 52 local Markdown links/anchors pass across the provider
contract, author guide, caller decision, milestone and checkpoint labnotes.
`git diff --check` passes; exact staged runtime, test and documentation diffs
were reviewed before committing. No hosted call, manifest enablement or secret
configuration change was performed.
