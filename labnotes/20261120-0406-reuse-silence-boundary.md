# Reuse silence boundary

A clean operational reuse epoch reset marked its entire first segment `partial_start`, even after fully admitted, source-mapped silent probability windows before onset. The flag previously cleared only after a speech endpoint. Reproduced this with sixteen consecutive silent windows following `provider_turn_settled`.

The narrow fix keeps initial attachment partial and adds a bounded silence-prefix witness only after clean operational-reuse settlement. Sixteen consecutive windows strictly below the existing offset threshold, while the diagnostic boundary is not speaking, clear the partial flag before the next onset. This reuses the existing offset-frame count and threshold; it does not change ActivityBoundary, operational VAD decisions, provider behavior or turn policy. A threshold crossing resets the streak. Every epoch/failure reset clears the witness, and non-clean invalid epochs retain existing rejection.

Astra approved the conservative witness: one low window or elapsed time is insufficient. Initial attachment, benchmark-only capture, immediate post-reset speech, fifteen silent windows and interrupted silence remain partial. Existing source admission, sample coverage and clock-position checks remain in place.

Verification:

- Red: 16 reused-worker tests, one expected failure: the first onset after sixteen mapped silent windows still carried `partial_start`.
- Green: 44 focused tests, seed 899933, covering reused worker, benchmark source worker and clean-reset report behavior. New cases check initial attachment, insufficient silence, threshold interruption, and complete onset/endpoint after the confirmed clean prefix. Existing gaps, missing prefixes and immediate-speech tests passed.
- Changed files formatted; diff whitespace check clean.

No model inference tests, provider requests, live calls or full-suite runs were performed for this checkpoint.

## Review correction: first observed operational epoch

Astra identified that initial attachment may first see a mapped batch from an already-running operational epoch (for example epoch 5), without witnessing its settlement reset. The existing implicit cursor transition synthesized a clean reset and accidentally enabled the new silence witness. Added a regression requiring that first observed epoch to remain partial even after sixteen silent windows. Red: 19 tests, one expected failure. Fixed the implicit-transition branch to withhold silence-prefix eligibility while preserving cursor/reset handling. Explicit clean settlement remains the only way to enable the witness. Green: 45 focused tests, seed 149129.
