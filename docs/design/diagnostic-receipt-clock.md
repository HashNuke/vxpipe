# Diagnostic audio receipt clock

VAD boundaries identify samples in accepted human audio. Their timestamps are
estimates on the server's receipt clock, not microphone acquisition timestamps.
Network and decoder scheduling can deliver contiguous audio faster than its
nominal duration. That alone does not mean samples or receipts moved backwards.

## Decision

Keep the existing nominal mapping for the first frame and for receipts separated
by at least the current frame's duration. A frame's final sample maps to its
receipt time; earlier samples subtract their remaining nominal duration.

For contiguous sample positions and sequence numbers with nondecreasing receipts,
let the previous receipt be P, the current receipt R, and nominal frame duration
D. When `0 <= R - P < D`, interpolate positions within the current frame over
`[P, R]`. Its endpoint remains R. Equal receipt timestamps map that frame's
positions to the same receipt timestamp, rather than inventing negative ordering.

Retain the existing uncertainty allowance: one millisecond plus the absolute
difference between receipt spacing and nominal duration. The source/resampler
uncertainty is still propagated. This describes an estimate; it does not claim
physical speech timing or impose a pass/fail threshold on the measured delay.

| Contiguous 320-sample frame at 16 kHz | Mapping | Uncertainty |
| --- | --- | --- |
| Previous receipt 100 ms, current 116 ms | Midpoint 108 ms; endpoint 116 ms | 5 ms |
| Both receipts 100 ms | All current-frame positions at 100 ms | 21 ms |

Do not interpolate across a source/sequence gap. Compression after a gap remains
unavailable. Backwards receipts, conflicting/reordered samples, unobserved samples
and expired retained boundaries keep their existing rejection semantics. Preserve
frame endpoint ownership so eviction cannot reassign an old boundary to a newer
receipt. A long receipt stall keeps nominal mapping rather than stretching audio
over the entire stall.

## Scribe event receipts

The Scribe socket records both the monotonic receipt time and the cumulative
number of audio samples successfully sent when it receives a transcript event.
The adapter uses that pair to associate the event with the human audio stream.
Its own sample count can already include a later write by the time it handles
the socket message. For example, an event received after 320 samples still
refers to 320 samples if another 320-sample write completes before the adapter
handles it.

## Alternatives rejected

- Rejecting every compressed interval discarded normal WebRTC observations.
- Clearing the uncertainty flag while retaining backwards nominal estimates
  could reverse adjacent mapped positions.
- Interpolating all intervals would stretch audio over network stalls.
- Altering call pacing or provider behavior to obtain regular receipts would
  change the conversation being measured.

## Evidence and verification

A live browser/Scribe call delivered consecutive frames with sample timestamps
advancing by 320 at 16 kHz and strictly increasing receipt intervals of
35, 15, 16, 19, 27, 16 and 16 ms. The old mapper marked each sub-20 ms interval
uncertain; 190 of 256 retained frames carried that flag. The call produced stored
rows but no usable acoustic timing estimates.

Focused checks cover the observed 16 ms interval, equal receipts, ordinary jitter,
long stalls, gaps, retention and resampling. The existing missing-source-sample
case, including a 961-to-320 sample rounding boundary, must remain unavailable.
Live functional readback verifies the resulting end-of-turn and barge-in timing
values independently of any performance budget.
