# Shared STS response-start grant

> Relocated from `docs/sts-response-start-grant.md` on 2026-10-09. First recorded source commit: `8e52be76db61` (2026-09-22T21:33:27+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260922-2122-sts-response-grants](20260922-2122-sts-response-grants.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [agent-speech-to-speech](milestones/agent-speech-to-speech.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Decision, 2026-09-22: an opted-in STS provider may announce a private model
response only through `response_started`. Caller end does not grant output in
that profile. This shared channel checkpoint binds event evidence to input
acceptance and consumer acknowledgement. It does not mint an authorization
origin, make policy decisions, integrate Google, or complete bounded origin
retirement; those remain in the [Google response plan](20260922-2053-google-sts-response-ownership.md).

## Design review before implementation

`Event.build` already validates closed fields and a positive signed-64 ordinal;
`EventDelivery` checks an accepted or exact staged context before enqueue, then
withholds delivery during a staged input. `EventQueue` supplies one exact ack at
a time. `STSOutput.admit` has one engine-owned credited output slot, but today
does not require start evidence. The new owner stores only bounded private
references and monotonic ordering; no process, public ID, transcript or PCM.

For each allocation, keep a high-water index and at most 16 pending starts.
Accepted positive indexes must strictly increase, with gaps allowed for silent
model generations. A duplicate (including after grant/rejection/retirement) or
conflicting reference at an old index cannot reopen work. The high-water mark
advances at channel acceptance of the start, including one later rejected by
the consumer. Exhaustion fails explicitly rather than wrapping or retaining an
unbounded tombstone set. Staged starts cannot be delivered before their input
accepts; a rejected first use with its own event fails the allocation as in the
existing early-event gate. Acceptance of a previously accepted distinct origin
while another input is staged remains valid and ordered.

An opted-in `Session.admit_output/2` must match the earliest pending exact
response reference. Until its exact `response_started` is acknowledged and its
context is accepted, no provider grant may be sent. A busy playback slot does
not consume the start; the consumer can retry after settlement. A successful
grant removes that pending start, with existing OutputState retaining the
generation/playback obligation. Non-opted STS providers keep their existing
caller-end admission behavior.

The consumer may instead reject an acknowledged pending response. Channel
removes only that response and sends a response-specific private discard
message to its provider; it does not issue a whole-wire interrupt or affect a
newer generation. Rejecting one response unblocks a later pending response in
order. Provider adoption of that message and policy-qualified capability queue
remain separate required checkpoints. A dead allocation, wrong consumer, stale
reference or unacknowledged start cannot reject a live response.

Rejected alternatives: reuse caller-end refs, current-epoch lookup at delayed
event arrival, granting from event shape without ack, unbounded retired-ref
tracking, discarding all Google wire content on one denied response, and
pretending this shared proof establishes provider resumption or public room
publication. All violate ownership or blur still-open acceptance gates.

Verification plan: owning-child red/green on real Session/Channel with an
opted-in controlled provider; cover pre-ack denial, accepted context, exact
grant/settlement, busy retry, reject/discard, stale/duplicate and ordinal gaps,
16 pending cap, >16 sequential retirements, wrong consumer, allocation teardown
and unchanged legacy STS. Keep the five Google controller reds separate. No
hosted call or full umbrella suite is a TDD red proof.

## Checkpoint evidence

The pure owner and real Channel/Session focused tests pass 33/0, including
25 sequential grants through the same allocation after one accepted context,
and the owning-child speech group passes 216/0 with three integration tests
excluded. These tests exercise the shared grant and provider notification with
a controlled provider, not Google wire behavior or policy-qualified origin
retirement. The separate Google controller red tests remain uncommitted until
that integration is implemented. No hosted call was made.
