# Phone recovery ordering

## Reproduction evidence

Initial Cartesia STT root acceptance at seed 149103 finished with one Gateway failure:
Telnyx custom-URL/destination loss reports missing source recovery speech.
All 1,718 CallEngine checks pass. The selected same-seed case passes in 2.3s;
the same-seed full Telnyx harness passed thirteen checks. At that point, no repair
was claimed.

## Ordering clue

The failed root log immediately before the assertion records source
`Capability.TextToSpeech` stopping on `Output.finish` returning `:wrong_turn`.
That request has zero generated PCM and the earlier 19-character acknowledgement
(`Connecting support.`); recovery speech remains queued behind it.
The harness's `PhoneHandoffAssertions.await_speak/2` completes that earlier
synthetic request with SpeechStarted/SpeechMetadata and no intervening audio.
The real OutputArbiter establishes a direct turn from its first credited PCM
frame, so a finish without any frame has no matching turn. Whether cancellation
already fenced that acknowledgement determines which path is reached.
This is a concrete fixture/protocol hypothesis, supported by the observed sink
error; final root causality remains to be verified.

## Next safe action

- [x] Reproduce the fixture's missing-audio contract deterministically before fixing.
- [x] Complete the synthetic acknowledgement with valid credited PCM before metadata,
  preserving fencing when handoff already canceled it; do not loosen sink turn checks.
- [x] Run focused owning checks and the Telnyx/Twilio recovery files.
- [x] Verify all root gates; keep this correction separate from Cartesia STT.

The initial STT same-seed rerun had no repair applied and passed 2,922/0.
Cartesia TTS (f6023cc6) and STT (28043981) were accepted and pushed before this
fixture checkpoint. No live telephony/provider calls, deadline increases or
production sink changes were made in this investigation.

## Deterministic regression and repair

Extracted the existing wait loop as a public function in test-only support,
without changing its behavior. Two checks exercise the actual Deepgram semantic
TTS allocation with active and zero-played fenced acknowledgement requests.
The active check uses the real Gateway OutputArbiter and a controlled AudioEgress
scheduler, accepts PCM credit, finishes the output and settles confirmed playout
before requesting recovery. The fenced check proves no acknowledgement PCM
escapes cancellation and the allocation admits recovery afterwards.

The initial run reports two checks, one failure: active acknowledgement emits
completion without any preceding audio. The fenced case already passes. The
repair inserts one 20 ms mono 48 kHz PCM chunk between SpeechStarted and
SpeechMetadata. Its 750 Hz tone is distinct from the recovery/cue proof tones.
The provider retains final metadata behind audio credit; existing fencing
discards these bytes when cancellation already owns the request.

Two intermediate test-only mistakes were corrected: OutputArbiter requires its
native readiness adapter; requesting replacement after generation completion
must wait for local playout settlement. Neither needed a runtime change. The
final selected regression reports 2/0 in 0.2s. The combined run before fixing
the settlement assertion reports 28 checks with that single new-test failure;
all 26 Telnyx/Twilio harness checks pass with the repaired fixture.

This proves and repairs the synthetic provider boundary violation. It supports
the initial failure hypothesis, but cannot prove every intermittent handoff
issue shares that cause. Sink validation, production deadlines and transport
semantics are unchanged. No billable telephony or AI request was made.

## Current gates

Format, compilation with warnings as errors, strict Credo and unused dependency
checks all finish successfully. The first fixture-repair root run reports
2,924 checks, one failure, 74 exclusions: the older after-speech-adoption
progress-notification assertion, rather than this acknowledgement regression.
The separate handoff-progress labnotes record its fixture contract correction.
The root run with both corrections also reports 2,924 tests, one failure,
74 exclusions. The failure is RTVI departure delivery from a test that ends
the room immediately after client-side channel opening. The separate departure
labnotes record the missing server readiness acknowledgement.

The root run with all three test corrections is terminal, exit zero:
2,924 reported tests, zero failures, 74 exclusions, seed 149103. It includes
all 1,718 CallEngine, 522 Gateway and 193 Console tests. All five root completion
gates pass for this test-fixture checkpoint. No speech/source-cutover runtime
state machine changed. ElevenLabs and final provider milestone acceptance remain
pending; the successful run does not establish exact interleavings in earlier
intermittent failures.
