# STS tool execution ownership

## Decision and checkpoint boundary

Room-authorized host operations use the existing `Tool.InvocationRegistry`,
`InvocationSupervisor` and `Invocation` beneath the exact STS allocation tree.
The execution budget remains 5,000 ms, with 16 outstanding invocations and
65,536 result bytes. Retired speech associations do not free invocation capacity.
The tree's temporary significant children fail together; loss of the capability,
room owner or explicit activation stop ends business workers without restarting
them. Ordinary speech interruption only retires provider associations.

A small tree-local completion bridge leases terminal observations from the
registry. It retains the leases privately and forwards observations to the room's
existing source/epoch/permission-checked publication path. No lease is consumed
by worker completion, public publication, or an ordinary provider result.
Uncertain deadline expiry remains `{:error, :unknown}`. Local worker termination
does not establish remote rollback.

This checkpoint preserves the pre-existing active-call final-result path; it is
NOT acceptance of the approved running-ack/private-continuation protocol.
Until that protocol is implemented, retained completions occupy capacity for
the allocation lifetime. This is bounded and deliberately does not discard a
result to permit more work. Cancelled associations never receive another result.

## Proposed shared seam (OPEN; parent coordination required)

After successful registry submission, send exactly one correlated ordinary
running acknowledgement. Add an explicit private engine operation, tentatively
`submit_tool_completion(capability, completion_ref, observation)`, distinct from
`push_text` and the retired provider call. Bounded admission is not commitment:
an ordered receipt must identify the exact allocation and completion reference
and report committed, rejected or interrupted. Only committed evidence may
acknowledge the registry lease; interruption releases/retries without execution.
No public caller turn is created. Pending projections and blocking/nonblocking
model admission must participate in this protocol.

Proposed coordinated write set: capability STS controller, `Speech.STSProvider`,
`Speech.Session`/channel command and event contracts, descriptor admission facts,
Morse and Google provider controllers, and their conformance tests. The parent
owns this shared seam and Google response work. This checkpoint changes none of
those files and does not claim this seam implemented.

## Design review (before tests/code)

Reuse the authoritative registry rather than inventing a second outcome store
or destructive queue read. A bounded bridge holds delivery leases, not execution
authority. Exact tree-local registry identity qualifies notifications; room
public IDs remain invocation IDs. Existing room checks still qualify result
publication. Put the bridge before the registry in child startup order, and
both before capability startup. Temporary significant children prevent silent
reconstruction after an invocation ownership failure. No synchronous bridge to
room callback is allowed. Test actual compiled room submissions, not only a
helper. Full binding/schema adoption and conversation admission remain OPEN.

Rejected alternatives: raw tasks with timers (no owner cleanup); cancelling
workers with speech (loses accepted work); consuming a lease after sending a
message (no acceptance proof); a second ordinary result on a retired call; and
pretending typed user input is a private continuation.

## Verification

Focused owning-child red/green evidence is recorded in the checkpoint labnote.
No native, load, hosted, billable or umbrella acceptance is part of this slice.

The final focused selection passes 83 tests, including 11 new compiled-room
lifecycle cases. These cover actual Invocation ancestry, interruption survival,
leased private retention, five-second unknown timeout, room/capability/activation
loss, registry/supervisor/bridge loss, and both running and terminal saturation.
Existing identity, policy and embedded transcript checks remain green.

Fault injection also exposed an existing generic worker privacy gap:
`Tool.Invocation` logged its state, including arguments, when its parent supervisor
was killed. The parent subsequently authorized a separate `format_status/1`
repair. Actual parent-loss and worker-termination crash captures first failed on
the synthetic argument, then passed with diagnostic logging enabled. The repair
sanitizes only state/message/reason/log; execution, timers, outcomes and startup
remain unchanged. The combined selection passes 99 tests. See
`labnotes/20260922-2025-invocation-crash-privacy.md` for red/green evidence.

This closes the demonstrated formatted crash-log exposure, not privileged VM
inspection: explicitly enabled OTP raw debug rings and `:sys.get_state` are
outside formatter protection. No child-start argument leak was observed in the
captured failure paths, and no generic startup/private-handle changes were made.
The new completion bridge separately redacts its status and failure messages.

## Admission deadline repair

Parent review found that the registry checked its absolute admission deadline
only before potentially blocked supervisor preparation. After both submit and
reconciliation reported unavailable, resuming preparation could still start
business work. Compiled-room and owning-registry regressions reproduced a late
running record. Registry now carries the original deadline through preparation,
checks it again before begin, and forwards it to Invocation's begin handler for
a final check before Task creation. Expired prepared workers are terminated
through their supervisor and never enter the registry. Existing direct begin
callers and the five-second accepted-execution budget retain their behavior.

The three new deadline checks and prior approved regressions pass together:
102 tests, seed 0, two schedulers. This is a separate repair after the privacy
checkpoint; see `labnotes/20260922-2031-invocation-admission-deadline.md`.
