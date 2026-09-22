# STS caller-turn publication

Status: focused implementation verified in embedded provider-controlled calls.
This refines the existing caller publication
tasks in [Agent speech-to-speech](milestones/agent-speech-to-speech.md), not the
response-triggering turn controller or the full hold/transfer contract.

## Decision and ownership

The STS capability acknowledges provider evidence before forwarding it. Caller
evidence carries the exact source identity, channel sequence, input epoch and
source audio/transcript intervals captured at onset. Immediate output fencing
stays in the capability; the room publication path must not interrupt again.

When STS supplies caller text, genuine onset opens a room-owned caller turn and
semantic turn end completes it. Text alone cannot invent either boundary.
The room correlates partial/final text and both boundary events with its own
command/turn IDs. Raw provider IDs remain private keys, including reference
values; their inspected strings are not public IDs or interchangeable keys.
When human STT is selected, its existing publication path owns the caller pair.
This does not select the controller that triggers the STS model response.

Keep at most 16 unsettled caller associations at each owning boundary. Final
text may arrive after semantic turn end and must retain the original public
IDs. Once both settle, remove the association. A channel-sequence watermark
rejects repeated/delayed owner envelopes without an unbounded retired-ID set.
Provider adapters remain responsible for deduplicating upstream events before
assigning fresh channel sequences. Overflow explicitly retires the allocation.

Room release assigns a fresh input epoch. Hold invalidates that epoch and clears
its caller associations. Recheck exact connection, capability, current epoch,
held membership and source policy intervals before publication. Never relabel
earlier accepted speech into a later transcript interval after revoke/regrant.
Repeated release while already open preserves the epoch. Transcript denial
suppresses end-event fallback text and releases the permitted completed turn's
association; it must not leak text or exhaust the pending budget after repeated
denied-text turns. Source intervals, not the global revision, permit unrelated
policy changes without relabeling the caller's evidence.

## Rejected alternatives and limits

- Publishing a turn from each transcript delta invents conversational boundaries.
- Reusing the onset notification to interrupt in the room can cancel the reply
  that already followed that onset.
- Using provider IDs as public correlations leaks private session identity.
- Keeping all completed provider references makes state grow with call length.
- Treating the new owner-message epoch as full provider-history isolation would
  overclaim: late upstream evidence first seen after release still needs the
  milestone's provider/session fencing and complete lifecycle verification.

## Verification

The initial embedded matrix reproduced missing caller starts in both modes
without human STT (five tests, two expected failures). Require one correlated
pair and exactly one final text in all four modes, including delayed human-STT
onset. Add focused room-boundary evidence for private IDs, late text, duplicate
and stale envelopes, exact source, epochs/policy, bounded state and cleanup.
These checks now pass. Further red cases caught denied-text fallback leakage,
retained denied-text associations, generic overflow failure attribution and
non-idempotent input release before their repairs. Complete external/hybrid
room control and provider-level late evidence after hold remain unproven.
Progress and acceptance limits are recorded in
[checkpoint labnotes](../labnotes/20260922-1514-sts-caller-publication.md).
