# Clean reset evidence

Operational reuse sends `provider_turn_settled` to close its inference epoch after normal provider turn settlement. SourceWorker explicitly treats this as a clean reset. LiveReport and BargeInTiming instead counted it as a failure anywhere between the relevant timing endpoints, suppressing already complete evidence.

Reproduced both primary metrics independently with pure LiveReport evidence: a fully covered speech endpoint and a uniquely owned interruption onset/acknowledged playback stop became unavailable solely because of clean settlement. The minimal fix excludes only `provider_turn_settled` from interval-wide acoustic and interruption invalidation.

Epoch closure remains unchanged. An incomplete old epoch cannot acquire progress after closure, borrow coverage from a new epoch, or fabricate a missing onset/endpoint. Genuine inference failures, gaps, source changes and clock uncertainty retain their existing handling. The old-epoch missing-coverage reason remains `inference_reset` when clean settlement closes incomplete coverage. Astra reviewed that contract explicitly. No turn policy, provider behavior, model behavior, projection bounds or persisted schema changed.

Verification:

- Red: 7 pure LiveReport tests, 2 expected failures proving endpoint and barge-in suppression independently.
- Green: 39 focused tests, seed 720377: clean-reset regression, boundary coverage, progress equivalence, BargeInTiming and reused SourceWorker.
- Negative cases cover actual inference failure, audio gap, source replacement, missing onset/endpoint and incomplete closed coverage; existing timing tests retain clock-uncertainty behavior.
- Changed files formatted; diff whitespace check clean.

No provider/live calls, model tests or full-suite runs were performed for this checkpoint.
