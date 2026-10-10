# Native TTS request admission

> Relocated from `docs/native-tts-request-admission.md` on 2026-10-09. First recorded source commit: `642779e0afe9` (2026-09-20T07:41:06+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260919-2322-pending-tts-acceptance](20260919-2322-pending-tts-acceptance.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [simpler-speech-integrations](milestones/simpler-speech-integrations.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Checkpoint D is paused after the early-admission implementation reproduced an
existing cancellation regression. This records the next request-lifecycle decision,
separately from the verified [cancellation repair](20260920-0041-native-tts-cancellation-findings.md).
No production room has migrated to this contract.

The [2026-09-20 complexity audit](20260920-0041-speech-complexity-audit.md) revises the next
implementation: Channel should own output credit/playback directly, and the
complete admission/cancellation/replacement/accounting workflow is one acceptance
unit. The custom receipt representation below was an earlier proposal and is
superseded by testing simpler owner-held historical facts first. The current
source and reproduced failure described here remain unchanged.

## Admission and provider submission

`Session.speak(allocation, text)` returns `{:ok, %Speech.Request{}}` after bounded
engine admission. The handle contains an engine reference, exact allocation,
current consumer, input character count, public usage identity and audio format.
It retains neither text nor audio. Provider callbacks and event/audio envelopes
continue using the handle's `ref`, independently of any upstream request ID.

Returning the handle must not wait for provider acceptance. The consumer can then
fence an admitted request while its provider callback is still pending. Synchronous
errors describe rejected engine admission: invalid bounded text, wrong authority,
not ready, busy, or an expired/failed admission. A successful admission does not
prove upstream submission or billable work.

The allocation retains its single persistent Input worker and original command
watchdog. `input_submitted` remains the actual submission evidence. A clean provider
rejection before submission produces one correlated engine `failed` event with an
allowlisted reason; the existing bounded event queue and acknowledgement rules
apply. Cleanup must complete under the original speak deadline before publishing
that failure. Recorded submission prevents treating a later callback error as a
clean unsubmitted rejection.

The public API and Channel both recheck the original deadline around Output
admission. The request handle uses Channel's current consumer after adoption,
rather than the allocation's original prepared role fields. No global executor,
per-request Task or automatic replay is introduced.

## Remaining cancellation and evidence work

These decisions are not yet implemented or accepted by the first admission tests:

- Retain one cancellation/report while the existing speak callback is pending;
  execute it after callback resolution without requiring consumer retries. Preserve
  the original speak, fence and cancellation-call deadlines independently.
- Accept genuine submission evidence for the exact fenced request without reopening
  its audio. Fencing does not prove an in-flight upstream write did not happen.
- A clean pre-submission rejection can isolate the request locally; it must not call
  provider cancellation for work the provider definitively rejected. A rejection
  after submission requires a failure path preserving its positive evidence.
- Preserve committed submission facts through both allocation and whole-scope loss,
  including when the consumer has not acknowledged the event. First test bounded
  immutable fact delivery to the existing independently owned usage consumer.
  Per-request state held only in ScopeControl disappears with scope loss.
  Historical evidence grants no new live authority.
- Preserve optional provider request IDs within their existing 256-byte bound and
  validated provenance. Numeric counters alone cannot retain arbitrary metadata.
  The evidence-delivery contract requires red tests before choosing its representation.
- Separate local generated-byte observation, sink credit and actual playback.
  Live snapshots are provisional; final snapshots require a terminal seal or
  confirmed retirement of all receipt writers. A `closed` notification can arrive
  before descendant teardown. Missing committed submission evidence after failure
  does not prove the upstream provider incurred no work.

An earlier proposed receipt used reference-counted storage retained by the consumer,
with bounded publication of metadata before a commit marker. That representation
is no longer the selected approach: it adds a publication protocol before testing
ordinary ownership and messages. OTP atomics' ordered integer operations and
reference lifetime do not establish the project's evidence-delivery contract.
[OTP atomics documentation](https://www.erlang.org/doc/apps/erts/atomics.html).

## Alternatives and implications

Keeping the synchronous facade would prevent the actual consumer from cancelling
while acceptance is held. Using a foreign test caller or weakening ownership checks
would not prove the intended contract. A second input worker would add concurrent
provider commands and a new ordering problem. Moving all request evidence into
ScopeControl adds a synchronous hop and fails whole-scope-loss persistence. A global
receipt table would introduce shared ownership and explicit retention cleanup.

The early handle changes the unaccepted native API; existing native tests and load
scripts need mechanical reference extraction. Production legacy APIs remain as
implemented. Provider submission, terminal isolation, playback accounting and bounded
failure handling remain mandatory rather than consequences of the earlier return.

## Verification and review

The first two tests use the actual consumer and an explicit provider-release barrier.
Before implementation both fail because the facade cannot return while acceptance
is held (2 tests, 2 failures, seed 530504). They require early admission without false
submission and a clean rejection followed by usable replacement audio.

GPT-6 Astra xhigh reviewed the tests and design independently: current adopted
consumer identity, bounded ordered failure delivery, retained original watchdogs
and rejection-after-submission handling are required. Receipt persistence, queued
cancellation and full replacement completion remain separate red/green slices.
See the [labnote](20260919-2322-pending-tts-acceptance.md).


## Introduced cancellation regression and proposed repair

The first two admission tests passed after implementation (2 tests, zero failures,
seed 530504). The broader selection then failed an existing held-credit cancellation
case: **122 tests, one failure** with the same seed. `cancel` returned `busy` after
an otherwise valid output fence.

A paired isolated test establishes the causal ordering. Both cases hold the Input
worker while the provider accepts E, then acknowledge submission and receive valid
PCM through the actual consumer. The control case lets Input deliver its result
before fencing/cancelling, and replacement remains usable. The failing case issues
cancellation before that Input result, then releases Input and proves its command
slot has cleared. The cancellation has already returned `busy`; the fence expires
with `command_timeout`, provider/Output/tree terminate, and replacement returns
`closed`. This is a failed allocation, not just a different return label. A callback
held beyond its own deadline does not explain it: the test releases Input and
checks completion before the fence expires.

```sh
# From apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/speech/tts_admission_cancellation_test.exs --seed 530504
```

The first paired run produced **2 tests, one failure**, in 0.7 seconds. The control
passed. This follows directly from early admission exposing the request while
Channel still marks Input busy. The previous synchronous facade returned only after
that slot cleared. The verified cancellation repair predates this newer API change;
its 1,897-test and load results do not certify the early-admission implementation.
Production rooms still use the legacy path; this reproduction uses isolated native
allocations, not a production call or a load-frequency measurement.

Proposed repair, pending the user's resumption after this tested pause:

- Retain at most one authenticated cancellation command/report while the matching
  speak operation occupies Input. Reply after executing that cancellation, rather
  than asking the consumer to retry. Do not queue arbitrary unrelated input.
- Preserve the original speak, fence and cancellation API deadlines. A genuinely
  stalled speak still expires safely; queueing must extend none of those budgets.
- Once the speak result arrives, resolve it before invoking cancellation. Genuine
  submission after fencing must remain evidence without reopening output. A clean
  pre-submission rejection isolates locally; rejection after submission cannot
  discard incurred usage evidence.
- Keep replacement admission blocked until the callback and terminal-isolation
  barriers complete. Retain the tested stale-audio, replay, authority and cleanup
  guarantees. No second worker, provider command race or global queue is needed.

Keep the paired regression red until the approved repair makes it pass. Then verify
pending acceptance, clean rejection, callback/terminal ordering, abandonment and
original-deadline variants; rerun relevant speech tests and load before acceptance.
Surviving historical submission evidence is required within the complete D workflow. No repair or
rollback was applied after this finding, and no D checkpoint was committed.


A strengthened same-seed rerun also produced **2 tests, one failure**, 0.7 seconds,
without compiler warnings. It explicitly proves the original Input slot is cleared
and that the later close reason is the fence's `command_timeout`. GPT-6 Astra xhigh
independently reviewed the causal barriers and queued-cancellation proposal. When
implementing the repair, the completion barrier should allow the matching cancel
to become the next Input immediately; an idle-slot assertion belongs only in the
current failure-evidence branch. This review does not accept a repair not yet made.
