# Human recovery boundaries

## Scope and audit

Continue the human-web failure-cleanup item after `347e255`. Existing native checks cover
destination loss after briefing, phase loss, wait-player loss, failed AI preparation and loss
during resource preparation/adoption/release. Engine checks cover cue failure and cancellation
after partial release. The remaining early human boundaries need received-audio evidence.

Extend the existing native recovery flow for private destination disconnect during briefing,
briefing voice failure, briefing expiry and expiry after the acceptance prompt. Use the configured
five-second total attempt timer for expiry cases, not a fabricated successful readiness result
or a longer production recovery budget. The existing web control profile has acceptance only;
declining means disconnecting or not accepting. Do not add a new reject command or UI control.

Every case must release the failed private admission once, stop the old phase, avoid destination
activation, recover the same caller/media actors, deliver the recovery cue and spoken source
response, and accept a subsequent caller turn. Assert bounded failure reasons for the new cases.
The existing destination-loss case additionally completes another transfer in the same call.

Earlier intermittent native recovery failure remains unestablished. New passing cases alone
cannot establish a causal fix; retain that concern until there is stronger failure evidence.

## Verification

The first four-case native run passes: four tests, zero failures, 55 excluded, in 59.5 seconds
(`vxpipe-human-recovery-boundaries-first.log`). All assertions described above hold, including
actual expiry before/after the prompt and exact bounded failure reasons. No production behavior
needed changing. Keep the original two-second admission-release assertion for non-expiry cases;
only the two cases awaiting their real five-second attempt timer need a six-second observation.

The retained historical root failure log identifies an actual recovery result of
`{:error, :unavailable}` in the destination-loss case. Other intentional failure tests in the
same log have different errors; those are not evidence about this failed case. The log does not
identify which recovery operation returned unavailable. Earlier isolated repeats and the full
native file passed. Do not infer that new passing boundary checks fixed this separate failure.

## Completed verification checkpoint

All five root checks pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The suite reports 1,405 tests, zero failures and 16 integration exclusions. Gateway has 392 tests,
including 58 default native startup/transfer cases; the public-URL case stays in its opt-in lane.
The runner's `vxpipe-recovery-boundaries-gates-results.json` records zero for every gate.

Changed documentation links resolve and `git diff --check` passes. Commit the focused native
coverage, testing guide, milestone/index evidence and this note together. The earlier recovery
failure did not occur in this full run, but its cause remains unknown. Keep the failure-cleanup
item and overall milestone unchecked; 20 checkpoint tasks remain.
