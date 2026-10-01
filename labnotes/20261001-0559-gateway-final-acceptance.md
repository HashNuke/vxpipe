# Gateway final acceptance

The completed provider-room root run is terminal, exit two, seed 232973:
3,031 tests, two failures and 97 exclusions. All 1,822 CallEngine and 195
Console checks pass. Twilio silent-wait/cue-loss recovery reports missing source
speech. Telnyx blocked-model startup/disconnection does not observe room DOWN
within its two-second assertion.

The Twilio trace shows the older 19-character acknowledgement receiving
`:stale_output_generation` after recovery has changed the sink generation.
The TTS capability then retires as `:audio_output_failed`. This establishes the
immediate observed failure path, but not the original scheduling cause.
The Telnyx trace has no corresponding provider failure; inspect teardown and
readiness before attributing it to the speech additions.

A same-seed selection of cue-loss and startup-disconnection tags runs both
carriers: four tests pass, 22 excluded, in 8.5 seconds. A passing selected rerun
is insufficient to declare either original cause repaired. The complete two
carrier harness files are being checked next. No remote carrier or paid speech
request is made in this investigation.

## Bounded reruns

The complete Telnyx/Twilio harness files pass all 26 tests, zero failures,
seed 232973, in 29.5 seconds. No Gateway runtime, fixture or assertion was changed.
A new full umbrella gate is running on the same final production source and
corrected room fixture. Record its terminal result before claiming acceptance.

The observed stale acknowledgement has a concrete sink rejection trace. Whether
it was submitted before the room held the source turn, and the exact ownership
ordering around that transition, remain unproven. Do not loosen sink generation
validation or prolong shutdown assertions based solely on a passing rerun.

## Terminal acceptance

The full same-seed root rerun exits zero: 3,031 tests, zero failures and 97
exclusions, seed 232973, including all 1,822 CallEngine, 522 Gateway and 195
Console checks. The earlier two Gateway failures are not reproduced; their
causes remain unproven. No Gateway runtime/fixture or deadline was changed.
All root gates and Lean pass. Three additional direct LLM startup cases pass
separately from the umbrella root, seed 752435, and the deferred hosted-agent
selection check reports three skipped, seed 680666. Those test-only additions
postdate CallEngine loading in the full run and are not included in its count.
Final formatting and Credo cover the complete files. Native input admission
is separately committed/pushed as `fb238b80`; the remaining acceptance checkpoint
contains its exact room/live fixtures, catalog seam, conformance, runner and
documentation. Milestone/index acceptance is synchronized with publication.
