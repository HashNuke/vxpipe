# STS public identities

## Baseline and plan

The previous goal turn was a verified wait on the still-live umbrella gate
session for committed checkpoint `f213bfb5`. Its Call Engine suite passes
1,032 tests; Gateway is still running. No restart was needed. The worktree
was clean at the beginning of this turn.

Continue directly under the user's later instruction; no delegation, hosted
calls, or remote pushes. Record discoveries/tasks before tests or runtime edits.

Inspection confirmed two public identity defects already covered by the open
milestone task: agent correlation IDs reuse provider identifiers, and event
publication selects an arbitrary non-monitor connection instead of the pinned
allocation source. A repeated start also replaces the live public command ID.
Split the milestone task into concrete agent-output, caller/retirement and tool
identity steps before implementation. Inspection additionally found public
`inspect(call_ref)` tool IDs and tool-only provider correlation fallbacks; that
newly identified work is recorded as a separate task, not silently included.

This checkpoint first fixes agent output identity and exact-source attribution.
Caller events, bounded generation-qualified retirement and tool-only identities
remain explicit subsequent work; passing this checkpoint cannot close B/C/F.
Public events continue through EventPublisher/TranscriptRouter. No provider,
transport, transcript-source, response-triggering or Google gating change is
needed for this step.

## Red/green evidence and decisions

- Eight new room publication checks all failed before implementation: provider
  IDs were exposed for strings/references, duplicate starts replaced IDs,
  wrong agents could publish, an unrelated connection was selected, invalid
  source bindings were accepted, missing connections raised, and allocation
  replacement retained old output associations.
- Added matching assertions to the five embedded-room conversation tests:
  all five failed on exposed reference IDs before implementation.
- Generate the public turn ID in RoomAuthority, retaining the existing private
  lookup key for now. Remember whether output text has already been published;
  complete/interrupted outcomes remove the active association. Pin the original
  connection PID in the turn and revalidate the allocation handle, participant,
  connection ID, role/admission and room incarnation at publication.
- Terminal handling with no current source discards the association instead
  of raising. Rebinding a capability clears its old output associations.
- All 13 new/strengthened checks pass. The older room fixture needed an explicit
  allocation input handle to match production ownership. Its no-binding readiness
  check now explicitly removes that handle instead of accidentally invoking a
  provider operation on the test process.
- The broader 101-test run first exposed an implicit 100 ms readiness assertion
  in the capability fixture while a native reproduction was running. Recorded
  the task first, then tied that assertion to the fixture's existing 5,000 ms
  `PrivateInit.open/2` deadline. No runtime or audio latency deadline changed.
- The complete focused startup/selection/room/policy/capability group now passes
  **101 tests, zero failures**, seed 0. Exact-file formatting and diff checks pass.

The previous root session ended with two Gateway handoff failures, not a green
gate; its separate labnotes contain the result. Recorded investigation tasks
before any repair. An isolated rerun of those two cases is still in progress.
The first failure missed ordered cue/conversation audio; the second observed
transfer completion instead of room shutdown after a release-loss injection.
Neither justifies a blind deadline increase.

Remaining identity work is deliberately not checked off: caller events and
IDs, generation-qualified bounded retirement (including late starts), and
tool-only/public tool-call IDs. No claim of final milestone completion.
