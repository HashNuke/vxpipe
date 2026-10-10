# Pending TTS acceptance

Previous goal turn made progress: the cancellation repair passed Astra review,
5,904 cancellation/replacement/STT cycles, 492 intentional fault/replacement trials,
and the final same-seed full umbrella rerun (1,897 tests, zero failures). The initial
two legacy Gateway timing failures remain recorded. R/A stay accepted, D remains
uncommitted and incomplete, and the full milestone goal is active.

## Early admission red and green

Added an explicitly gated Morse-delegating test provider and two tests through the
actual consumer. Red: **2 tests, 2 failures**, seed 530504, 1.2 s; neither call could
return engine admission while the provider callback was held. The desired API now
returns a typed Request containing identity and public metadata, with no text or
audio. Provider events still correlate with its raw `ref`. The current adopted
consumer comes from Channel state.

Channel retains the original Input watchdog after early admission and stops replying
to that original caller a second time. Clean pre-submission rejection completes
Output cleanup under the original deadline before publishing one bounded, ordered
failed event. Provider-submitted work cannot use that clean-rejection path. API and
Channel recheck admission deadline. No worker or global state was added.

Green: **2 tests, zero failures**, same seed, 0.2 s. Astra cleared the explicit test
barriers and bounded design. Added explicit Request type/current-consumer assertions
following review. Receipt persistence and queued cancellation are separate next slices.

Existing native tests/benchmarks now extract `request.ref`; production consumers are
still legacy. Rejection tests now observe the correlated failed event rather than a
synchronous provider error. The deadline tests retain their original equality/late
cleanup/descendant-teardown assertions and additionally reject late clean failure
publication. The handoff benchmark's rejection latency now includes failed-event ACK;
historical JSON stays unchanged. Broader focused checks are running.

The design is recorded in `labnotes/20260920-0041-native-tts-request-admission.md`. A consumer-retained
bounded receipt is preferred over a ScopeControl ledger to survive whole-scope loss.
OTP's documented atomics ordering/lifetime informs the representation; project-owned
publication, authority, snapshot finality and metadata bounds still need red tests.


## Introduced regression and pause

The broader focused selection ran **122 tests, one failure**, seed **530504**,
3.2 s. Existing `TTSCancellationTest` foreign-old-ticket case failed earlier in its
setup because held-credit cancellation returned `busy`. Early admission had exposed
a live request while the original Input result was still pending.

Added paired `tts_admission_cancellation_test.exs`. Both cases suspend only Input
while the provider is released to accept E and produce held valid PCM. The control
resumes/settles Input before cancelling and passes. The failing case cancels first,
then resumes Input and verifies the command slot is nil. The already-rejected
cancellation never runs: fence expiry reports `command_timeout`, exact descendants
terminate, and replacement is closed. First run: **2 tests, one failure**, seed
530504, 0.7 s. No runtime repair was applied after that reproduction.

Tightened the proof to assert cleared Input state and the fence's exact timeout
category, and removed compile-time constant-branch test warnings using test tags.
The user explicitly requires reporting and pausing when changed code is proved to
cause instability. That condition applies here, unlike ordinary missing-feature
red tests: previously working held-credit cancellation can now retire the allocation.
The proposed bounded queued-cancellation repair is in the admission design document.
Earlier root/load passes do not certify this source. No D checkpoint commit.


The strengthened paired test reproduces the same outcome without compiler warnings:
**2 tests, one failure**, seed **530504**, 0.7 s. Exact closed reason is
`command_timeout`; Input is already cleared before that fence expiry. Astra
independently confirmed the causal barriers and the new API scheduling window.
The Input-first control passes. This is isolated allocation instability, not a
production-room or general OTP finding.

For the eventual repair, Astra noted that the diagnostic helper's `input: nil`
assertion should remain in the failure-evidence branch or allow the exact queued
cancel as the next Input. A correct implementation may dispatch cancel immediately
after clearing speak; do not require an idle slot between them. Preserve proof
that the original speak command/watchdog is gone.

Milestone/index and the earlier repair report now distinguish their historical
passing evidence from this newer paused source. The bounded queued-cancel proposal
is reviewable in the admission document. Work stops pending the user's resumption;
no runtime repair, rollback, D acceptance or commit followed this reproduction.
