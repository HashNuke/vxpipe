# Human handoff failure cleanup

## Failure boundary review

Existing engine cases cover early/duplicate acceptance, private capability loss, destination loss,
cue loss, deferred drain expiry, stale policy and release acknowledgement invalidation. Native
cases cover retained-source recovery and input/output loss. Remaining failure work includes
asynchronous cancellation during release and cancellation racing a queued recovery success.
The previously intermittent recovery failure remains unexplained; this work does not claim to fix it.

## Reproduced defects

Deterministic engine cases show an attempt entering `recovering` after media release has
already opened an output, when its timer fires or its phase dies.
The generic failure path cancelled the phase and discarded the destination before trying source
restoration, even though the destination policy had already been installed. The approved release
boundary requires closure because restoration after partial release cannot safely be retried.

A separate case pauses the actual recovery worker after successful release, queues cancellation
before its real success result at RoomAuthority, then resumes the authority. The previous code
sent itself a failure message without changing pending state. The already queued result was
handled first and incorrectly published `recovered`. This reproduced without a wall-clock sleep,
fabricated readiness result or increased recovery budget.

A release-error archive case also failed: the room closed without a participant-transfer failure
fact. The explicit failed transfer was missing from the asynchronous history boundary.

## Changes and rationale

Latch the first failure in the existing pending handoff state for both recovering and releasing.
Any already queued result observes that cancellation before accepting success. Release cancellation
uses the existing terminal release-failure path, stops the phase, publishes failed status and records
a bounded failure cause/restoration outcome. It does not discard/recover an already adopted
participant as if it were still private. Existing whole-room supervision owns final resource cleanup.

Keep the original attempt and 750 ms recovery deadlines. No new public state, retry mechanism,
provider reconnect, UI component or orchestration process is introduced.

Retain the pending destination recognizer binding after main admission until release completes.
Its provider-unavailable notification and capability/ingress monitors must still fail this attempt.
After completion there is no pending transfer; ordinary connection lifecycle owns subsequent loss.
The capability, participant, connection and room identity checks remain unchanged.

## Verification

- Red: deadline and phase loss during outstanding release incorrectly reported `recovering`;
  queued recovery cancellation incorrectly reported `recovered`.
- Red: explicit release error failed to emit its transfer-failure archive fact.
- Red: adopted destination STT loss closed the room without transfer-failure progress. The corrected
  test also checks the specific failure cause in its archive fact and absence of recovery/success.
- Green: nine focused engine cases pass, including existing release invalidations, phase loss during
  policy adoption and the new cancellation cases. Release failure facts retain their bounded cause.
- Green: both native caller/desk cases pass with deadline cancellation or required destination STT
  loss while release is paused. The caller receives failed RTVI progress; all connections close
  without destination activation, recovery or redial.
- Final root gates pass: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test --max-cases 4 --seed 235296`, and
  `mix deps.unlock --check-unused`. The suite reports 1,386 tests, zero failures and 16 integration
  exclusions (638 engine tests; 377 Gateway tests). The public URL integration was not rerun for
  this failure-only change; its previous acceptance evidence remains separately recorded.
- Changed Markdown links resolve and `git diff --check` passes. The checkpoint still leaves
  22 broad milestone tasks; it does not claim complete failure-stage or human-slice acceptance.

## Review corrections and verification detours

The first failure matrix used loss of completed briefing TTS during release. Review found that this
would codify an unnecessary lasting dependency: completed private playback is no longer demanded.
Replace that case with loss of the still-required destination STT. Completed briefing-resource
retirement remains concrete work under the existing private-resource cleanup task.

The first full root run passed format, compile and Credo but failed one existing adoption test:
it required the old incidental `shutdown` reason; the corrected cancellation path now emits
`handoff_release_failed`. Update it to assert that explicit closure and no recovery or success.
Dependency validation was not reached in that run.

Loss of an adopted STT policy enforcer can concurrently stop the room supervisor. Its tests allow
that `shutdown` or the coordinator's `handoff_release_failed`, while still requiring transfer-failure
progress, the engine failure fact and no activation/recovery. This does not relax the call outcome.
The final engine red run, with only the adopted-binding change temporarily removed, failed at the
missing `failed` progress assertion; restoring it passes all nine focused cases.
