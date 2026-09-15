# Native audio routing verification

The previous goal turn made progress: `036232a` committed listener changes before
acceptance, and `071704e` corrected a tool-worker test monitor race. Transfer
acceptance and all 653 engine checks pass. The final 1,435-test umbrella run has
one ordinary human-only WebRTC audio failure; the root test gate remains open.

The restrictive-routing case fails at specialist output in the umbrella, passes
alone, then fails at initial caller-to-receiver output in its complete six-test
module. No transfer is pending in this test. Do not infer a policy cause from
the test's title or change runtime deadlines without evidence.

Use a temporary diagnostic only on timeout to collect RTP packet counts,
ingress sequence/readiness, output hold/readiness and mixer queue/drop counters.
Do not dump peer certificates, connection identities, audio or complete process
state. The diagnostic does not change the packet stream or add readiness waits;
it will be removed after tracing the missing packet boundary.

All four diagnostic runs of the complete six-test module passed: 16.4, 16.0,
14.9 and 15.8 seconds. No timeout counters were captured. Restore the original
test and make no production change on that evidence. The earlier failures remain
unexplained; these passes do not establish a fix.

Source inspection shows a 200 ms input jitter buffer and a 300 ms mixer playout
delay. The fixture sends individual packets with fixed RTP timestamps, including
a one-second gap around membership change. Packet arrival, decoding and mixer
lateness are plausible boundaries to inspect if the full run reproduces again;
none is proven responsible. Avoid widening deadlines, adding packet retries or
changing policy behavior merely to obtain a green run.

Continue the explicitly required preparation-stage listener work while retaining
the root failure as an open verification item. Keep this bounded research note
with that next checkpoint so the unsuccessful diagnostic pass is not repeated
without new evidence.

The next full umbrella run passed all five root gates: 1,435 tests, zero failures
and 16 exclusions, including all 410 Gateway checks. It used module preloading,
serialized test-file compilation, seed 235296 and four async cases. The ordinary
routing failure did not recur with the original test restored. This closes the
current root verification gate without establishing a cause or production fix;
retain the earlier failure evidence if the same symptom recurs.
