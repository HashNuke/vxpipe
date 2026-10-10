# Native TTS streaming

Previous checkpoint A was concrete progress: committed as `935d554`, all gates
passed, 2/9 accepted. This task starts D before any room migration.

## Initial design review

GPT-6 Astra xhigh reviewed a bounded topology: Channel remains the allocation
and request authority, Output owns one credited PCM envelope and playback
counters, and persistent Input executes provider commands. No additional
controller, global execution queue or per-frame Task is needed.

Review identified these implementation gates before acceptance:

- One delivery sender and explicit ready/submission acknowledgement gates prevent
  audio overtaking control evidence across processes. Output notifies Channel
  asynchronously; Output never synchronously calls Channel/provider.
- Actual current consumer authority must follow adoption, including prepared
  allocations whose original consumer is nil.
- Cancellation fences before sink interruption and provider cancellation, including
  cancellation queued behind held speak. Its original deadline still applies.
- Generated, accepted and actually played audio are different counters. Exactly
  credited final PCM permits generation completion; confirmed playback settlement
  permits replacement after normal completion. Cancel after completion emits no
  second terminal event.
- Session issues a fresh request reference. Reusing a caller's reference cannot
  relabel late old audio. Retain bounded current/last settled metadata only.
- Audio validation checks freshness before sink use; credit follows sink
  acceptance. Sink-generation fencing still owns any write already in progress.
- Preserve native Morse format/config limits, default 20 ms chunks/pacing,
  payload redaction and a 15-second audio-credit deadline.

## Red test

The first streaming test starts the intended native provider, synthesizes `E`,
acknowledges bounded PCM, and independently checks the 20 ms sine dot and fourteen
silence units at 8 kHz. It requires submission then one generation completion.
Initial execution failed because the native provider/API does not exist; no
ready event was delivered. This is the intended unimplemented-contract red test.

## Initial streaming implementation

Added the native Morse TTS session, typed audio/request events, an allocation-local
credited Output worker, and bounded speak admission through the existing Input
worker. The standalone streaming test passed (seed 69452). The combined speech
and Morse selection passed 101 tests (seed 177159) before the regressions below
were added. D1 is complete; D2/D3 are partial, and cancellation/playback/demo/load
work remains. No D checkpoint has been accepted or committed.

## Review findings and tested pause

GPT-6 Astra xhigh found two regressions in the interim source review:

- Channel checks its original deadline before synchronously authorizing Output,
  but does not check again before activation/readiness delivery.
- The audio input handler lacks a descriptor-kind guard, so audio submitted to
  native TTS invokes an unsupported callback and becomes a session failure.

Added `tts_deadline_test.exs` before attempting either repair. Running it from the
call-engine child produced **2 tests, 2 failures**, seed **530504**, in 0.5 seconds:

- The test commits Output authority within the startup budget, suspends Channel
  across the absolute deadline, then resumes it. It receives `:ready` sequence 1
  instead of the expected closed notification. This isolates the new synchronous
  handoff; it does not estimate how often the interleaving occurs under load.
- After ready acknowledgement, `push_audio` on native TTS returns
  `{:error, :session_failed}` instead of `{:error, :unsupported_operation}`.
  The subsequent valid-speak assertion is not reached.

The reviewer also identified a fresh-timeout issue in rejected-input cleanup;
this has source-review evidence only and still needs its own red test. The
two-phase cancellation ticket design was reviewed but remains unimplemented.

Implementation is paused under the user's explicit tested-instability rule.
The uncommitted source and red tests are preserved for repair; no rollback or
additional implementation was performed. Existing rooms use the legacy path.
Full umbrella gates and D load diagnostics have not run. R/A remain the last
accepted baseline at `935d554` (2/9 checkpoints).

The [finding report](20260920-0041-native-tts-deadline-findings.md) records causal limits,
the proposed original-deadline/authority recheck and kind guard, and required
repair/load/acceptance gates. Milestone and index now reflect the pause, including
correcting the index's stale R-only review row. No `WORK COMPLETE` notification
is appropriate while the full milestone remains unfinished.

## Remaining D review after authorized repair

The user resumed and approved the repair documented in
[repair labnotes](20260919-2159-repair-tts-handoff.md). Astra separately reviewed
the remaining D2–D5 contracts while the root suite ran. The next red test should
fence a held first `E` chunk, prove stale credit/validation rejection, report zero
actual playback after sink interruption, require one cancelled terminal, and
independently verify `T` on the same allocation. Different text detects accidental
old-output reuse. Keep the existing Channel/Input/Output processes.

Before the held-provider-acceptance cancellation slice, resolve consumer-visible
request identity: current `Session.speak/2` returns its generated reference only
after the provider callback returns, while the authorized consumer is blocked.
A foreign caller would not prove cancellation under the real authority model.
Possible bounded engine admission must preserve later rejection/submission/terminal
evidence; no such API change has been implemented in the repair.

Playback reports and cancellation tickets still need exact authority, monotonic
request totals, cumulative deltas, bounded replay metadata and original deadlines.
Cancelled sink drain after generation completion must not emit a second terminal.
Final-credit completion, abandoned fences, done/cancel races, long output, limits,
redaction and ownership-loss isolation remain acceptance work. The repair load's
simulated sink acceptance is not controlled playback completion. D4's checklist
now records these ordered slices, separately from implementation progress.
