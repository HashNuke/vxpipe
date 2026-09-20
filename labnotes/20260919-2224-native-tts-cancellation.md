# Native TTS cancellation

The preceding turn made concrete progress: the authorized handoff repair passed
all five root gates (1,886 tests, seed 801819), independent review and four serial
load lanes. This task continues D4; R/A remain the only accepted checkpoints.

## Initial red/green slice

Added public-boundary tests for fencing an uncredited `E` chunk, sink-confirmed
zero playback, exactly one cancelled terminal, and independently checked `T` PCM
on the same allocation. Replayed old audio credit/emission and the completed
ticket must not disturb replacement. Repeated fencing preserves the same ticket;
a completed result remains readable after its mutation deadline; a conflicting
playback replay rejects. A second test abandons a fence and monitors provider,
Output and allocation-tree teardown by the original budget.

Initial run: one missing-API failure (seed 465428). Expanded pre-implementation
run: **2 tests, 2 failures** from missing `fence_output/2` (seed 831595).
After the first implementation: **2 tests, 0 failures**, seed **607107**, 0.8 seconds.

Channel owns a cancellation watchdog from fencing, and reuses Input for the
provider callback. Output invalidates exact credit and keeps generated/accepted
bytes separate from supplied actual playback. Provider callback success and
generation terminal isolation both precede slot release. Morse clears its encoder
and ignores stale old timer/credit messages. No process or shared queue was added.

Astra reviewed the design: retain a completed result under a fresh bounded read
deadline, authenticate its exact ticket/current consumer and never admit a fresh
mutation token for that cache hit. Every facade invocation has its own admission
token, so a foreign caller with an old ticket cannot retire a replacement merely
by timing out in the Channel queue. Original deadlines bound all mutations.
Only current/last cancellation metadata is retained; older eviction must reject.

Current code review and broader tests are pending. Pending-acceptance cancellation,
ongoing actual-playback reports, normal playback settlement, further terminal and
deadline races, and D5 demo/playback load remain open. The preceding repair's
root/load results do not certify this subsequent cancellation implementation.

## Reviewed defects and tested pause

The broader speech/Morse/STT-usage run passed **111 tests**, seed **844779**,
before adding the next two regression cases. Astra source review identified:
settled-fence replay incorrectly closing the allocation; delayed old audio being
retained and released by replacement submission ACK; and a missing post-handoff
deadline check on cancelled terminal publication. The last issue, repeated pending
fence expiry and accepted-but-uncredited actual playback remain review-only findings.

Added two focused public/protocol tests. Running the cancellation file with seed
**670445** produced **4 tests, 2 failures** in 0.8 seconds:

- Repeating the settled fence returned `{:error, :command_timeout}` and an actual
  subsequent replacement speak returned `{:error, :closed}`.
- A replayed real old Output envelope was delivered after the replacement's
  submission ACK. The replacement provider was held after acceptance, so new audio
  could not hide the observation. This simulates a queued cast; it does not measure
  a real-world race frequency or prove audible playback of stale PCM.

These are defects in the new cancellation implementation, separate from the
previously verified handoff repair. Work is paused under the user's explicit
tested-instability instruction. The code and red tests are preserved uncommitted;
no repair or rollback was performed after reproduction. Production rooms retain
the legacy providers and R/A remain the accepted baseline (2/9).

The [finding report](../docs/native-tts-cancellation-findings.md) records evidence,
repair proposals, review-only concerns and the remaining acceptance gates. A
`WORK PAUSED` notification reports the stop; no `WORK COMPLETE` notification is
appropriate while the full goal remains unfinished.
