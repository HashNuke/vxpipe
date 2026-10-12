# Stabilize onset test

## Failure and cause

- Required umbrella verification for the toolbar work failed in the existing
  external-mode queued STT onset test with error stale_frame.
- Running the entire STSTranscriptModesTest file with the umbrella seed 541905
  reproduced the same precondition failure in the hybrid variant. An isolated
  location run passed both variants, demonstrating the timing sensitivity.
- The media ingress rejects frames received at or before the stream cutoff.
  The fixture uses millisecond monotonic time and tight retries; audio submitted in
  the cutoff millisecond can remain stale across those retries.

## Correction

- Use the file's existing manual_stt_clock helper in both queued onset variants.
  stt_frame advances its atomics clock, placing each frame deterministically
  after the cutoff. Keep the queued-message, privacy and no-turn assertions.
- No runtime, protocol, source-cutover or speech state-machine transition changed;
  this is a fixture clock configuration correction, so Lean replay is not needed.

## Verification

- Red: 37 tests, 1 failure with seed 541905 before the clock correction.
- Green: all 37 tests in STSTranscriptModesTest passed with seed 541905.
- Formatting, warnings-as-errors compilation, strict Credo and unused dependency
  checks passed after the fixture correction.
- Full umbrella rerun passed with seed 541905: 3,566 tests, zero failures.
