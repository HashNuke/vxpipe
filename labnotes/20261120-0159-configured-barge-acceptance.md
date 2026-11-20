# Configured barge-in acceptance

## Scope

Exercise the ordinary configured room, two independent human STT sources, local
Scribe transport, actual AcousticObserver boundary state and local Deepgram TTS
transport. Human B interrupts an output answering human A. The deterministic
classifier recognizes marker PCM, so this proves runtime correlation and durable
measurement plumbing, not native Silero accuracy or live provider behavior.

The test will independently hold the sink acknowledgement and provider Interrupt
control reply. Persisted stop offsets must fall after sink release, before the
held-provider observation and before provider release. Evidence must belong to B's
run and identify A's old output/source/connection. It must remain durable while B's
turn is accepted but not completed, then revise the same row after STT completion
with duration equal to stop minus acoustic onset.

## Work in progress

Configured fixture extension and a Console-owned held-Interrupt transport are
written. Existing ordinary fixture defaults are preserved. The optional test sink
acknowledgement helper is intentionally not implemented until the focused red run.
Mix lane currently belongs to the parent/reviewer; no commands have been run yet.
No Telnyx, live provider, production deployment or commit.

## Implemented and verified

The configured test now uses two separate human connections and STT allocations.
A's ordinary model answer starts acknowledged playback; B's source receives
marker PCM and its Scribe partial initiates the ordinary interruption path. The
sink holds its acknowledgement until explicitly released. A Console-owned wire
wrapper independently holds the provider Interrupt reply. The test verifies the
persisted stop timestamp is after sink release but before provider hold/release,
so provider cancellation wait cannot inflate the metric.

B's accepted-but-uncompleted turn is already durable with interrupted output
metadata. After B's STT turn completes, that same row revises to an available
stop-minus-onset duration. It retains A's old output, source, connection and turn
identity while belonging to B's participant/connection/run/clock. A's report has
no borrowed barge-in evidence. The room is stopped and diagnostics drain.

The first observed acoustic segment is intentionally partial in SourceWorker.
A deterministic speech/silence preroll clears that condition before the measured
onset; production correlation was not relaxed. A prior attempt correctly remained
unavailable with partial_start-derived clock_uncertain. The initial frame assertion
also had to select the exact output correlation instead of an unrelated wait-audio
frame already in the mailbox.

Red evidence: the selected configured test reached the missing defer_interrupt/2
helper and failed with UndefinedFunctionError. The new sink helper is opt-in;
ordinary interruption still follows the same immediate acknowledgement path.

Final verification:

- Configured cross-human acceptance: 1/1, seed 444389, 58 excluded; log
  vxpipe-configured-barge-final.log. The prior complete pass was seed 55749; the
  final rerun additionally checks B's stored clock and connection identity.
- Existing output/semantic cancellation plus new diagnostics tests: 19/19,
  seed 678560; log vxpipe-configured-barge-sink-regression.log.
- Changed files formatted and git diff --check clean.

This verifies fallback benchmark observation with deterministic probabilities,
not native Silero accuracy, operational-reuse acceptance, live Scribe or physical
remote audibility. All command sessions are terminal; Mix lane is returned to the
parent. No production changes, full suite, live provider, deployment or commit.
Independent GPT-6 Astra xhigh review reran the final configured case (1/1, seed 0),
inspected the holding controls and source identities, and returned clean.
