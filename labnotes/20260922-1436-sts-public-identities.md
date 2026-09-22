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

## Commit and post-commit verification

Committed as `6f5bb3f8` with exact-path staging and cached-diff review before
starting broader gates. Push notification sent. Root format, warnings-as-errors
compilation and strict Credo pass; the full root test run remains live. Do not
restart it merely because an observation returns no output.

The isolated Gateway rerun completed: **two tests, zero failures**, seed 0,
158.9 seconds. Command from the Gateway child:

```shell
PGHOST=/var/run/postgresql mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs --name-pattern 'five-participant handoff retains|human handoff gates destination and closes after release loss with silent_all waits' --seed 0
```

Read-only follow-up found that the release-loss test waits for the mock transport
to terminate, then continues the paused native gate. The actual STT capability
sends `vxpipe_stt_unavailable` to the room independently; once handled during
release, `HumanHandoff.fail/3` latches failure before accepting worker completion.
Transport termination alone does not prove that the room has handled that
message. This is an ordering hypothesis, not a proven cause. Added a concrete
controlled-order/acknowledgement task before any further test/runtime repair.
The gate helper also has a bounded 1,000 ms auto-release, matching the native
gate call bound; do not simply lengthen either deadline. The missing audio
sequence still needs peer/generation-specific evidence and remains open.

The root run subsequently completed with exit status 0: all five gates pass,
**2,199 tests, zero failures, 42 excluded**, seed 0. The earlier two Gateway
failures remain investigation tasks; a passing rerun does not establish a cause.
This result covers identity checkpoint `6f5bb3f8`; the later Google output
changes started after this run's Call Engine suite and need their own gates.
