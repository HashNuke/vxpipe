# Repair TTS handoff

The user resumed the goal and explicitly approved the proposed repair after the
tested pause. R/A remain accepted at `935d554`; D remains uncommitted and partial.
The previous turn made progress by preserving two deterministic regressions and
the finding report. This task repairs those paths before continuing D.

## Red and green

Expanded the two existing red tests with adoption, original rejection-cleanup
budget, and late rejection-reply coverage. Adoption and late rejection suspend
the API caller as well as Channel, so facade timeout cleanup cannot mask the
Channel decision. The tests use barriers and original-deadline timers.

Before repair: **5 tests, 5 failures**, seed **530504**, 2.7 seconds. Startup and
adoption released late readiness; late rejection left Channel running; cleanup
extended its deadline by 22 ms in the controlled run; wrong-direction input
returned session failure.

Changed Channel to recheck the original deadline/allocation after Output
authorization, reject audio for TTS before ticket admission, preserve the original
input deadline through rejection cleanup, retain the input watchdog until that
cleanup returns, and recheck the deadline/allocation before replying.

After repair: **5 tests, 0 failures**, same seed, 1.7 seconds. Added explicit
provider, Output and allocation-tree DOWN assertions on the failure paths for
the next focused run. No latency or capacity claim follows from these unit tests.

GPT-6 Astra xhigh reviewed the failure evidence and minimal repair scope. It
confirmed the caller-suspension requirement and requested descendant teardown
proof; no additional handoff escape was identified. Repaired-source review,
load diagnostics and broader gates remain pending.

## Expanded containment and load evidence

The broad speech/Morse run initially failed because the startup test's generic
receive observed a new provider `:DOWN` before the closed event. This was a test
ordering assumption introduced with the teardown monitors, not another late
readiness failure. Changed it to select the closed event, reject late readiness,
and separately require all descendant DOWNs. The same-seed rerun passed
**106 tests, zero failures** (315087).

Added `bench/tts_handoff.exs`. Its initial 36-trial run passed 3,936 TTS requests,
3,936 STT turns and 492 Output-failure replacements, but reviewer feedback correctly
limited its initial interleaved-STT and timing claims. Strengthened it to complete
STT with TTS credit still withheld in seven rounds, label candidate setup including
lease work, and document observed fault bounds, ACK timing, selective-receive
ordering limits, fixed run order and no warmup. The final run passed the same
counts with process count 245 after every trial, empty dynamic-child sets and
84.8–87.3 MB total memory. TTS failure/replacement maximums were 2.546/2.547/5.550 ms
for notification/teardown/readiness, with the first two observed after sibling STT.

Serial STT reruns passed 68,400 latency turns and 39,360 concurrent-fault turns
(72 trials). STT safe/teardown/replacement maximums were 3.916/16.991/6.745 ms;
the larger teardown observation is retained without classifying it as unsafe
failure or estimating a regression from a single tail value. Reports are stored
under this labnote's timestamp. Adoption rerun and full umbrella gates are next.

Root format, warnings-as-errors compilation and strict Credo pass. Astra's repaired
source and revised benchmark review found no remaining repair blocker. D's wider
cancellation/playback work is not accepted by this bounded repair evidence.

The serial adoption rerun passed **36 trials and 16,236 turns** in 136.3 seconds.
The final four diagnostic workloads total 131,868 successful measured turns plus
492 deliberately failed TTS requests; these are different workloads, not one
continuous production capacity test.

## Completed repair verification

All five root gates passed on the repaired source. Full `mix test` used seed
**801819** and passed **1,886 tests, zero failures, 40 excluded**: MCP 37,
Agent Runtime 95, Call Engine 788, Calls 117, Gateway 460, Artifacts 20,
Persistence 184 and Console 185. Gateway took 370.1 seconds; its longer run
continued making progress and was not restarted. Unused dependency-lock checking
also passed. No runtime source changed during those checks.

Final documentation links, JSON artifacts and diff whitespace checks pass.
The repair is verified; the full goal stays active with R/A accepted (2/9), D's
cancellation/playback slices next, and no D checkpoint commit yet. A progress
push notification reports the repair result; `WORK COMPLETE` remains reserved
for the completed full goal.
