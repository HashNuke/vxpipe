# Sample clock compression

Actual WebRTC receipts for contiguous 320-sample (20 ms) frames arrived 16 ms apart. The old nominal start calculation put each later frame's estimated start before the preceding frame endpoint, so it marked otherwise ordered audio `clock_uncertain`. The reviewed live sample showed 190 of 256 retained frames affected and all five endpoint rows unavailable.

For contiguous samples and sequence numbers with nondecreasing receipts, compressed frames now map their interiors monotonically between the previous and current receipts. Their endpoint remains the current receipt. Equal-receipt batches collapse to that receipt. Existing uncertainty remains `1_000 + abs(receipt_delta - frame_duration)`; this is a server-receipt estimate, not a microphone timestamp.

First and noncompressed frames retain the original nominal arithmetic exactly, including source/resampler rounding. Stalls are not stretched across audio. Compression across an audio gap remains unavailable; backward receipts, reordered frames, changed epochs, before-run positions, shared-boundary ownership and retention behavior are unchanged. No model, provider, turn policy or LiveReport filtering changed.

Verification:

- Red: SampleClock and timing foundations, 14 tests with 3 expected failures. Strengthened the prior permissive foundation check to require an actual monotone position; reproduced 16 ms receipts and equal-receipt batching.
- Green: SampleClock, timing foundations, AudioTimeline, SourceWorker and reused SourceWorker, 57 tests passed, seed 359092. Includes unchanged 961-to-320 source-rounding chronology and explicit gap-plus-compression rejection.
- Changed Elixir files formatted; diff whitespace check clean.

Astra reviewed the mapping partition and formula before implementation. No live provider or full-suite run was performed in this checkpoint.

Final independent Astra xhigh source and design review is clean. Actual live
functional readback remains pending; no numerical delay threshold is required.
