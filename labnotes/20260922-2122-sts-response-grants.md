# STS response-start grants

Baseline `d0fee186`, with only five deliberate Google controller reds left
uncommitted. The input context and early-event delivery checkpoints are
committed; focused speech group 204/0 and four static gates pass. No hosted
calls. This note tracks the shared response-start boundary, not Google adoption.

## Design review before tests/runtime

Read the milestone's open response-ownership tasks, `docs/google-sts-response-ownership.md`,
`docs/sts-input-context.md`, Event/EventDelivery/EventQueue, STSOutput and legacy
STS conformance tests. The channel already serializes event enqueue/ack, input
acceptance and output admission. A small pure owner can keep bounded private
response refs and the allocation-local high-water mark; Channel keeps IO and
consumer identity checks. The consumer's exact event ack is necessary before
grant, and the context must be accepted by then. A denied response needs a
response-specific provider discard, not a wire-wide interrupt.

## Red/green checkpoints

All tests below ran from `apps/vxpipe_call_engine`, with `ERL_FLAGS='+S 2:2'`.
The pure `response_starts_test.exs` started at 6 failures because the owner did
not exist; after the bounded owner was added it passed 6/0. An additional red
for reusing a still-pending reference at a larger ordinal failed 1/6; the
pending-reference check made it 6/0. Real Channel tests added to
`sts_input_context_test.exs` produced four expected response-grant/disposition
failures in 25 tests after the fixture was made capable of emitting controlled
responses. The shared Channel/EventDelivery/STSOutput/Session binding made the
focused pair pass 31/0. A test assertion was corrected to distinguish a busy
active slot from a stale response after settlement; this was a test expectation,
not a production behavior change. The broader owning-child speech group passed
214/0 (three integration tests excluded). A final real-Channel sequential
retirement regression passed as 32/0 focused tests and the speech group then
passed 215/0 (three integration tests excluded). No full umbrella test was
used as TDD red proof and no hosted call was made.

The final cross-allocation stale-reference regression passed with the focused
pair 33/0 and the speech group 216/0 (three integration tests excluded).
Independent Astra xhigh read-only source review found no actionable defect;
it did not review Google adoption, policy or origin retirement.

The owner advances its signed-64 high-water mark at event acceptance, stores at
most 16 pending starts, and keeps no retired-reference set. Event delivery
binds accepted or exactly staged input before enqueue. Only an exact consumer
ack followed by accepted context can grant the oldest pending start. A busy
output slot leaves the start pending. Consumer rejection sends a response-local
discard notification and cannot reopen the ordinal. Legacy descriptors bypass
this new grant check. The test fixture observes grants and discards without
representing Google wire behavior. Normative provider contract documentation
now records the boundary and leaves policy, Google adoption, discard handling,
and origin retirement open.

Post-commit static gates are pending for this checkpoint.
