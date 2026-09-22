# Scope

Continue the independent audit's output-STT delayed-final reproduction after
the ordered tool checkpoint `f0b48e0b`. That checkpoint's root format,
warnings-as-errors compile, strict Credo and unused-lock gates pass. The full
root test remains pending coordinated Gateway integration; no new root pass is
claimed. Parent owns these runtime files; parallel agents own Gateway and load.

Expanded the existing milestone failure-isolation task before tests/code:
timeout and still-live finalization-error sessions must retire before a next
reply; restart failures must invalidate the old identity immediately and preserve
the selected transcript source, with explicit bounded exhaustion. Multiple
recognition segment/success-boundary settlement remains separately open.

## Design and evidence

The current timeout only marks `stt_text` failed and keeps the session. The
finalization-error path assumes the recognizer will die and emit a closed event,
which is not a callback contract. The provider-loss handler also admits queued
work before replacing the failed recognizer. Use the existing owned session
retirement and readiness path; do not introduce a second provider or historical
audio replay.

The output-STT suite reproduces **13 tests, two failures** before runtime
changes: timeout and an error-returning but still-live recognizer both fail the
old-provider `DOWN` assertion. The controlled fixture permits valid channel
endpoints and an acknowledged finalization-error reset on a replacement, so the
green test must also prove next-turn recovery instead of merely stopping work.

The retirement fix gives **13 tests, zero failures**. Added a queued-reply test
with a recognizer that initializes once but rejects every replacement: **14
tests, one failure**, because bounded `:restart_failed` never arrives. Inspection
shows successful session reservation resets the counter before readiness, so
asynchronous startup failure can retry indefinitely. Preserve attempts across
reservations until acknowledged readiness; retain the selected sidecar on
exhaustion and explicitly stop the owning capability rather than changing to
provider transcripts. This is the existing planned exhaustion gate, not a
timeout increase.

The exhaustion regression is green: **14 tests, zero failures**, seed 0. It
requires capability/tree `DOWN`, a bounded number of startup attempts and no
queued second-turn admission or transcript-source fallback. Retirement tests
also send an old-allocation endpoint after replacement and require only the
replacement's real-channel final text. Recognition failure now cancels the
outstanding text timer; delayed close events from retired allocations are inert.

The joined STS capability, room identity/publication, activation and provider
tool/control suites pass **135 tests, zero failures** (seed 0). Tightened the
regression setup to monitor the original recognizer before beginning ONE, then
reran all 14 output-STT tests with seed 77: zero failures. This avoids letting a
fast rejected finalization replace the recognizer before the test captured it.
Exact changed-file formatting, whitespace checks and 45 local documentation
links pass. Commit before broader gates; the multi-segment/success-boundary,
sidecar startup/format and persisted-usage tasks remain open.

Parallel load implementation `962c98d4` returned for review. Parent read its
methodology and all support modules, identified cross-sender timing attribution
at the barge transition, and asked the same agent for a separate red-green fix
before integration/measurement. No ten-call performance result is claimed.

After commit `d47513b7`, all four non-test root gates pass. The complete Call
Engine child suite also passes: **1,102 tests, zero failures, 14 excluded**, seed
0, two schedulers, 104.8 seconds. It was started before the next egress test
edits and verifies the committed recognizer/tool source, not those new tests.
The full umbrella/Gateway run remains pending handoff integration.
