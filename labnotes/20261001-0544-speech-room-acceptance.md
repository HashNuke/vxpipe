# Speech room acceptance

## Focused boundary gap

The acceptance audit finds compiled startup and standalone allocation evidence
for Cartesia STT and Cartesia/ElevenLabs TTS, but no actual room cases with those
specific selections. Add local compiled room tests with owning CallEngine
fixtures. Keep real-provider protocol evidence separate; no new paid request is
needed for these consumer boundaries.

Five cases first report four failures in 0.9 seconds: the Cartesia STT room case
passes, while both TTS providers fail startup because the trusted request-module
setting is rejected. Their existing runtime already exposes that private seam;
the closed settings validator omits it. This is a local test-composition failure,
not evidence that ordinary default production requests cannot start.

## Coherent correction and acceptance

Align the trusted settings catalog for Google, Cartesia and ElevenLabs request
TTS with their existing runtime: default to the provider's request module and
allow the private request-module seam. Public Call Spec options still reject
request/transport hooks. Google shares this same request ownership path.

The five room cases then pass, seed 223965, in 1.2 seconds. Cartesia caller PCM
reaches the owned wire and correlated cumulative/final transcript publication.
Both TTS selections route echoed agent text through credited PCM and finish only
after acknowledged sink playout. An incoming caller turn interrupts each,
retires the old owned request worker and admits clean replacement output; stale
old audio cannot publish. The additional agent-output assertion verifies that
Cartesia final input reaches the model consumer as well.

A root-invoked focused command without the workstation database socket setting
fails at database startup before tests. Rerun from the owning child rather than
claiming a behavior failure. Final root format/compile/Credo/dependency, Lean and
same-seed default checks are running on the complete source.

## Existing Gateway gate failure

The prior full run reports 3,026 tests, one failure and 97 exclusions,
seed 232973. All 1,817 CallEngine and 195 Console tests pass. Gateway's existing
five-participant WebRTC handoff times out waiting for 250 Hz audio after monitor
detachment. Its same-seed individually selected rerun passes one test, 67 excluded,
in 168.7 seconds. The original intermittent cause remains unproven; no Gateway
logic or fixture change is made from that narrow passing rerun. The final full
same-seed gate is required before milestone completion.

## Final fixture acknowledgement and gates

A focused rerun after the model-output assertion exposes a readiness fixture
race: readiness resources were read before ingress track preparation completed.
Use the public ingress preparation acknowledgement for the same provided track
before reading resources. All five corrected cases pass, seed 698496, in one
second; production source is unchanged by this test-only correction.

Format, warnings-as-errors compilation, strict Credo and unused-dependency
checks all exit zero. Lean build, oracle drift and replay pass: one test, zero
failures, seed 116049. The full root run loaded the earlier five-case file
before this acknowledgement correction and passes all 1,822 CallEngine tests;
the corrected file passes separately above. The root run finishes with 3,031
tests, two Gateway failures and 97 exclusions, seed 232973. All 195 Console tests
pass. The new Gateway investigation records the two failures rather than
claiming full acceptance from successful narrower suites.

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
