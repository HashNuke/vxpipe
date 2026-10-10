# Atomic STS input contexts

> Relocated from `docs/sts-input-context.md` on 2026-10-09. First recorded source commit: `46322435801e` (2026-09-22T21:02:55+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260922-2045-sts-input-context](20260922-2045-sts-input-context.md), [20260922-2103-early-sts-events](20260922-2103-early-sts-events.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [agent-speech-to-speech](milestones/agent-speech-to-speech.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Status: input-only boundary implemented; 74 focused checks pass. Parent response
integration and full lifecycle acceptance remain open.
This does not implement response-start admission, private tool continuation,
policy-origin minting or Google cross-origin handoff.

## Scope and decision

Add closed `response_context: reference` options to `Speech.Session.push_audio/3`,
`push_text/3` and `input_activity/3`. Preserve the two-argument entry points and
legacy dispatch for descriptors which do not opt in. Unknown, duplicate or
malformed options must fail before input delivery. For an opted-in STS descriptor
(`response_start?: true`), a context is mandatory and the provider must implement
optional `STSProvider.submit_input/3`. Its operation is exactly `{:audio, pcm}`,
`{:text, request_ref, text}` or `{:activity, boundary}`. Never fall back to a
legacy callback after a missing or rejected context-aware callback.

Reuse Channel's existing consumer check, readiness gate, command deadline,
atomic claim and single ordered input slot. The context and operation cross the
provider boundary in one invocation, not a set-context message followed by input.
Stage context state before dispatch to Input; settle it only when Channel accepts
the exact claimed worker's result within the original deadline. A callback may
emit semantic events before returning. Staging therefore supplies correlation,
not accepted-input authority or permission to grant output.

## Approved pure owner seam (input-only interim)

`Speech.ResponseContexts` is immutable state stored in
`Channel.response_contexts`, not another process or global registry:

- `new/0` creates an empty owner.
- `stage(owner, context, command_ref)` returns `{:ok, owner}` or a bounded
  rejection. It permits only one outstanding input reservation and at most 16
  retained contexts, including first-use staging. Both references must be opaque
  references supplied through the checked engine boundary.
- `accept(owner, command_ref)` commits that exact reservation, marking first use
  accepted; a stale command cannot commit another reservation.
- `rollback(owner, command_ref)` removes an unsuccessful first-use reservation,
  but preserves a previously accepted context when later input is rejected.
- `status(owner, context)` returns `:unknown`, `:staged` or `:accepted`. Reusing
  an accepted context while its next input is pending does not erase its earlier
  acceptance. A separate reservation query can expose that pending command if
  parent response binding needs it.

Proposed future obligation seam: `retain(owner, context, obligation_ref)` and
`release(owner, context, obligation_ref)` use exact idempotent reference holds,
not unchecked increment/decrement counters. They must never turn staging into
acceptance or evict a context still needed by input, response or tool work.
The parent must coordinate hold bounds and the authority for releasing the last
accepted-origin root before this part is implemented. No wire retirement or
grant protocol is included here. Pending that coordination, accepted contexts
remain retained until allocation teardown; the seventeenth distinct context is
rejected, while further input using an existing accepted context remains usable.
There is no latest-context pointer, automatic replacement or guessed cutover.

The capability owns minting, immutable policy evidence and reuse while that
evidence is unchanged. The parent owns how response/tool obligations pin a
context and when old origins become releasable. This owner does not infer those
facts from callback order, caller IDs, playback settlement or response count.

## Separated design review, before tests and runtime

Source inspection confirms Input currently claims the Channel slot before calling
the provider, and Channel already checks exact allocation/consumer, active state,
deadline and callback occupancy. Minimal hooks can stage before Input submission
and settle after accepted result validation without adding another queue.
Prepared allocations have no consumer and cannot issue usable contexts. Timeout
already fails the session; it must never produce accepted context state.

The parent's Russell-reviewed atomic-delivery design was read in the parent
worktree without edits. Its explicit cross-origin limitation is preserved:
same-context multiple model responses must remain possible; an opaque reference
does not prove which unlabelled Google wire interaction produced later content.

Rejected alternatives: provider-global mutable context, staging after invocation,
activation on semantic emission, silent legacy fallback, automatic eviction of
the oldest context, or reference counts with no retirement authority/bound.
Each either loses atomic correlation, invents acceptance or loses live ownership.

Parent approved this input-only seam and allocation-lifetime retention before
runtime. This is explicitly INTERIM, not full bounded response-origin lifecycle
acceptance. Do not implement retain/release in this checkpoint. Before full
milestone acceptance, the parent must integrate bounded exact response/tool
obligation holds and engine-authorized root retirement, and prove more than 16
sequential fully retired origin rotations without unbounded tombstones.
Consumer-owned context references cannot be provider-issued. Failed first use
must become unknown even after early provider semantics; staging never grants.
No shared Event/STSOutput, capability or Google edits are authorized in this slice.

## Verification and remaining integration

Real Session/Channel and controlled provider probe tests first proved the missing
boundary red, then covered exact atomic operations and legacy dispatch; closed
options; absent context; unsupported provider; wrong consumer; prepared state;
callback busy; expiry; staged state observed inside callback before its return;
first-use acceptance/rollback; reuse rejection retaining earlier acceptance;
and 16-context saturation without eviction. Pure tests cover stale reservation
settlement and bounded owner transitions. Early semantic handling remains a
parent integration requirement, not a claim that staging alone admits responses.

The focused group passes 74 tests, including 15 new owner/boundary checks. Actual
early `input_submitted` emission followed by rejection leaves first use unknown.
This is not a `response_started` delivery/grant proof: the parent owns that work.

The existing Channel activates input on readiness, not on the consumer's ready
acknowledgement; the unready test explicitly withholds provider readiness instead
of changing that legacy contract.

For parent integration, the context is stored before Input can claim its command.
Channel's exact-worker result handler calls `STSInput.finish_context/3` only after
checking the original deadline and allocation validity. Event emission must return
after bounded local staging, without waiting for consumer acknowledgement, so a
synchronous provider callback can return its acceptance result. Parent-owned
EventQueue gating was still required at this input-only checkpoint; it was not
included in the original 74-test implementation.

Only focused Call Engine child tests with two BEAM schedulers and this worktree's
independent build/dependency copies are permitted. No root, native, hosted,
load or billable runs. Record exact red/green terminal results in
`labnotes/20260922-2045-sts-input-context.md` before a runtime checkpoint commit.

## Early-event delivery follow-up

Consumer delivery of opted-in semantic events is now deferred while an input
callback is pending, without blocking the provider's `Event.emit`. Only an exact
accepted callback releases queued evidence. A rejected callback with
input-attributable or otherwise ambiguous early evidence fails the allocation
before publication; an explicitly separate response from a previously accepted
context remains queued in FIFO and survives that rejection. A late
`response_started` for an unknown/rolled-back context, or one borrowing a
different staged context, is rejected at the Channel boundary. This is event
correlation and delivery safety, **not** acknowledged-start output grant,
policy-origin verification, bounded origin retirement or Google adoption.

The follow-up's focused test file passes 21/0 and the owning-child speech group
passes 204/0 (3 excluded), seed 0, two schedulers. Red/green chronology and
independent review findings are in
`labnotes/20260922-2103-early-sts-events.md`.
