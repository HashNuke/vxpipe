# Diagnostic transport timing acceptance

## Scope

Added Gateway boundary tests connecting its actual Opus normalization to Engine's
public `AudioTimeline` API. WebRTC cases start with RTP packets, preserve receipt
time and source epoch through decoding/downmixing, and cover linear16 16/48 kHz
and Opus with its decoder-owned PCM. Local carrier-envelope cases cover mono
16 kHz Opus normalized to linear16 8/16/48 kHz. No Telnyx implementation or fixture
was changed, and no provider/network call was made.

This is acceptance of existing behavior, not a runtime change. The new tests
assert receipt-to-sample mapping, 20 ms packet loss, late/reordered packets,
compressed/backwards receipt clocks, source timestamp reset and a successor epoch
with a fresh clock origin. Unobserved or uncertain samples cannot become valid
positions; old epochs cannot be stitched into a new run.

## Evidence and limits

| Contract | Evidence |
| --- | --- |
| Decode/rate conversion preserves source receipt and sample units | New `diagnostic_audio_mapping_test.exs`: real native Opus decoding, 320 normalized samples per 20 ms packet, exact 0/20/60 ms positions. |
| Missing/reordered audio cannot fabricate continuous timing | New boundary tests retain an unobserved 20 ms gap and reject a late packet; duplicate accepted PCM returns the unchanged timeline. |
| Clock/source reset invalidates old mapping | New boundary tests reject backwards receipt/sample clocks and foreign epochs, then independently establish the successor's clock. |
| Queued WebRTC input stays on its original epoch | Existing `source_receiver_test.exs` and `connection_source_cutover_test.exs` cover receiver barriers, old/new frames and failed cutovers. |
| Local carrier packet identity and sample units | Existing unchanged media decoder and audio ingress pipeline fixtures cover chunk sequence, timestamp advancement, identity and stale packet rejection. |
| Socket receipt/epoch survives queued carrier dispatch | Existing `telephony_media_socket_test.exs` covers fixed socket receipt time, hold/arm epoch rotation and an old frame stalled in the dispatcher; `media_session_test.exs` rejects stale epochs and verifies source hold/arm. |
| Diagnostic recurrence and report invalidity | Existing Engine source-worker tests reset recurrent state on gaps, preserve delayed receipt time and reject duplicates; LiveReport/TurnTiming retain incomplete endpoints and null acoustic durations across gaps/resets. |

Initial run: 10 passed, 2 failed because the first test matrix incorrectly assumed
22,050 Hz is a supported diagnostic rate. `CapturePacket` explicitly admits only
8/16/48 kHz. Kept that restriction, covered 8 kHz conversion and added an explicit
22,050 Hz rejection test. Successful carrier conversion alone does not imply
diagnostic support. No implementation was changed to make this expectation pass.

Current checks:

- Gateway boundary and existing transport fixtures: 53 passed, zero failures,
  seed 207028; includes all 13 new tests.
- Engine timeline/clock/source-worker/live-report/turn-timing: 64 passed, zero
  failures, seed 429180.
- Existing local socket/media-session epoch cases: 5 passed, zero failures,
  seed 104449. No live-provider lane was used.
- Root format, warnings-as-errors compilation, strict Credo and unused dependency
  checks pass. Independent Astra xhigh review is clean after the epoch assertion
  fix; independent final baseline passes 13/13 and its fault control produces the
  same 12 expected failures. The scoped offline transport task is complete;
  accuracy, stress/load and live acceptance remain open.

Review reproduced an assertion gap: replacing every normalized frame's source
epoch with one fixed, wrong epoch still passed all 13 tests. The original test
constructed its timeline from that already-normalized epoch. Added independent
equality against each incoming frame and passed the replacement source through
normalization before establishing its new clock. The same wrong-epoch control
now fails all 12 mapping/reset cases at the expected equality assertion; the
unsupported-rate rejection case remains valid. Final real-path selection:
13 passed, zero failures, seed 313397. This was a test weakness, not a reproduced
production defect. No runtime correction was needed.

This does not establish live Telnyx support, real network loss behavior, acoustic
accuracy or measured overhead. Those claims are outside these offline checks.
No UI/runtime/source state-machine change; no browser/full-suite/Lean rerun needed
for this test-only checkpoint. Final full gates remain after milestone work.
