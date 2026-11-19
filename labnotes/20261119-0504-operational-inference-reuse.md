# Operational inference reuse

- Continued after accepted-audio checkpoint `2c3a3f76`, with a clean worktree.
- Added a prospective diagnostic subscription on ConversationalSTT's existing
  operational Silero stream. Native allocation generation and handoff owner must
  match. Capability audio-tap attachment forwards its handle to the wrapper using
  direct non-suspending delivery; no DB read or extra inference admission occurs.
- Diagnostic context is captured before each existing inference submission. On
  completion, the already-computed probabilities are offered with operational
  recognition epoch, first per-epoch 16kHz sample cursor and monotonic observation
  time, before ordinary stale-epoch suppression. Warmup has no diagnostic context.
- The existing provider-settlement reset also emits a diagnostic reset marker and
  preserves all original control-state resets. Inference failure emits a fixed
  notice, then takes the same original failure path. No model load, inference,
  cancellation, operational reset or canonical speech event is added by the tap.
- Mid-stream subscription reports partial_start and waits for the next operational
  reset before mirroring. This avoids adopting pre-subscription in-flight/pending
  audio. The next stream starts at its own epoch/sample zero. Old-epoch late
  results stay explicitly old; consumers must never merge them into a newer run.
- Three focused contracts first failed for the missing observe API. Affected
  diagnostics, wrapper and source-attachment tests now pass84/0. They prove one
  classifier submission for each offered fixture chunk, preserved operational
  onset during diagnostic revocation, and exclusion of work predating subscription.
- This is an operational reuse hook, not a completed run collector. Automatic
  source-worker admission, standalone benchmark-only inference, transport/sample
  correspondence, full on/off/source matrix, persistence and live accuracy remain
  pending. No combined milestone C task is marked complete. Astra review and
  static/Lean verification follow.

- Astra proved three integration gaps. Prepared/adopted allocations keep an
  immutable nil consumer, so checking that struct denied valid subscriptions.
  Source mismatch was fenced only after provider admission, allowing operational
  inference to emit into the old handoff while capability admission waited. An
  accepted trailing odd PCM byte was omitted from prospective coverage checks.
- Retained adopted-allocation, blocked-admission/source-replacement and odd-byte
  subscription/reset regressions. Adoption was red1/4, source/byte cases red3/7.
  Subscription now routes asynchronously through the live Channel's current
  consumer authority; no synchronous control-path authorization call was added.
  Source preflight revokes mismatches before provider admission, while PCM copies
  remain after acceptance. Existing operational odd-byte retention is unchanged;
  it keeps diagnostics partial across reset until a clean epoch is established.

- Static verification caught Channel's800-line SRP cap. Extracted only the
  diagnostic request/forward responsibility into Speech.DiagnosticSubscription;
  Channel delegates its routing. Affected rerun88/0 and final static gates pass.
  Lean passed after the behavior fixes and on the final extracted source (exit 0).
- Astra xhigh final re-review clean on the extracted version, independently34/0:
  original reproductions plus late epochs, foreign owners/stale generations,
  projection failure and saturation. Full umbrella run from the previous checkpoint
  completed with exit 0, including Engine2600/0, Gateway891/0 and Console591/0;
  it predates these edits and is not final current-source milestone acceptance.
