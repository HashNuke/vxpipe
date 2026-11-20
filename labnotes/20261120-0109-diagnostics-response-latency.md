# Diagnostics response latency

## Boundary and ownership

The next measured stage is canonical audio-turn completion publication to matching
text-capability dispatch invocation. It is independent of diagnostic collection:
a test-only OTP trace session watches only each configured RoomAuthority PID,
matching audio `ParticipantTurnCompleted` publication and `SendText` dispatch.
This includes activity completion, interruption handling and any greeting queue
delay before dispatch; it excludes capability execution, model latency and audio
egress acknowledgement. The existing successful configured response trace remains
mandatory.

The production telemetry contract intentionally excludes correlation identities;
expanding it or enabling diagnostic collection for the disabled baseline would
change the evaluated behavior. Observer-mailbox timestamps would include unrelated
consumer delay. Neither alternative is used. Match specifications emit only
source/turn/command IDs, with `:arity` preventing function arguments (State and
conversation content) from appearing in trace messages. No return, inherited,
all-process or content tracing is enabled.

Astra design review confirmed the selected boundaries and required local tracing
of `EventPublisher.publish/4`, whose default three-argument wrapper calls it
locally. OTP's monotonic trace timestamp is nanoseconds; conversion explicitly
uses nanoseconds to microseconds. Snapshot fences each exact authority PID,
including exited PIDs, and waits for every delivery acknowledgement before
returning samples. The supervised temporary probe owns the session's strong
handle, with explicit teardown and OTP handle-lifetime cleanup. The
[OTP trace interface](https://www.erlang.org/doc/apps/kernel/trace.html) defines
these session, timestamp and delivery semantics.

Raw source identities, canonical turn identities and boundary events are retained.
Warm membership uses the predetermined provider-settlement frame schedule, never
observed response duration; a late final dispatch stays in the population.
Complete matching boundaries are required for every canonical turn, including
warm-up, with nonnegative intervals and monotonic per-room event order. Overflow,
missing records, conflicting identities or duplicate stages invalidate the phase.
Egress acknowledgement remains a separate open stage; the current workload is a
text-response fixture.

## Focused verification

Artifact names refer to the host temporary directory.

- `vxpipe-response-trace-red.log`: both initial probe tests fail on the absent
  module; `vxpipe-response-trace-green.log` passes 3/3, including actual boundary
  capture, selected PID/audio-only filtering, arity/identity shape, bounded
  overflow and a delivery fence after authority termination.
- `vxpipe-response-latency-red.log`: three tests fail on the missing summarizer
  after correcting an initial test-comprehension syntax error. The green log
  passes 3/3 for complete multi-input populations, rejected missing/duplicate/
  mismatched events, and a late final dispatch retained in p95.
- `vxpipe-response-python-red.log`: missing independent validator import fails
  before implementation. `vxpipe-response-python-green.log` initially passes
  60/60 diagnostic Python checks, including required runner integration.

The initial configured disabled phase `vxpipe-response-latency-warm-off` completes
with 22 raw boundary events, ten measured dispatch samples / p95 254 us and 625
ingress samples / p95 277 us. Resources: 19.999050 seconds, 0.74 CPU-seconds /
0.037002 cores, HWM 206232 KiB, maximum threads 11 and 201 resource samples. Owned
scope/database cleanup is clean. This is initial instrumentation evidence, not
paired acceptance. Review subsequently reproduced the canonical ordinal/cohort issue below; this
initial artifact is not relabelled as corrected-validator evidence.

## Canonical-order review correction

The independent review control swapped the first and final canonical turns'
correlation/command IDs while retaining their ordinals and the raw trace. Both
validators accepted reassignment of a 50,000,010 us measured p95 to a 10 us p95 by
moving the slow final turn into warm-up. Retained Python and Elixir cases reproduce
this before correction (`vxpipe-response-order-red.log`,
`vxpipe-response-order-elixir-red.log`). Expected identities now retain source index
and ordinal; completion traces must advance that ordinal in sequence per input.
Dispatch interleaving remains allowed. Focused Console checks now pass 4/4 and
Python checks pass 61/61. New native phases will use identical corrected-validator
provenance; the original disabled artifact remains separate evidence.

## Corrected configured warm evidence

The valid corrected pair is `vxpipe-response-latency-warm-off-reviewed` and
`vxpipe-response-latency-warm-on-reviewed`. Each completes with ten measured
canonical turns, 22 raw response boundary events / ten measured dispatch samples,
782 raw ingress receipts / 625 measured ingress samples, 201 resource samples and
clean owned scope/database teardown. Maximum thread count remains 11.

| Collection | Dispatch p95 | Ingress p95 | CPU seconds / cores | Duration seconds | HWM KiB | PCM pacing p95 ns |
| --- | --- | --- | --- | --- | --- | --- |
| Off | 252 us | 266 us | 0.70 / 0.035001 | 19.999619 | 207392 | 197377 |
| On | 1094 us | 287 us | 2.80 / 0.140006 | 19.999084 | 252852 | 282914 |

Preliminary dispatch p95 delta is 842 us and ingress delta is 21 us, both within
the unchanged 2 ms stage budgets. CPU delta is 0.105006 cores, still above the
0.08-core one-input budget. This is one preliminary pair, not repeated full
performance acceptance. Egress acknowledgement, cold startup, database CPU,
inference coverage, other topologies/repetitions and accuracy remain open.

The first corrected four-input reuse attempt
`vxpipe-response-latency-warm-reuse-reviewed` is rejected by the unchanged resource
boundary gate: initial read completion is 2,612,427 ns late, beyond 2 ms. It exits
nonzero with clean scope/database teardown. This artifact is retained and is not
valid performance evidence; a separately named retry uses unchanged limits.

The valid retry `vxpipe-response-latency-warm-reuse-retry` completes two rooms with
two human inputs each: 94 raw response events / 41 measured dispatch samples,
p95 237 us; 2500 measured ingress samples, p95 321 us; per-input measured turn
counts 10/11/10/10. Resources are 19.998758 seconds, 8.57 CPU-seconds / 0.428527
cores, HWM 289516 KiB, maximum threads 11 and 201 samples. PCM pacing p95 is
210084 ns; owned scope/database cleanup is clean. This verifies source/command
correlation across inputs and operational reuse, not matched reuse overhead.

Root format, warnings-as-errors compilation, strict Credo and unused-lock checks
pass (`vxpipe-response-format.log`, `vxpipe-response-compile.log`,
`vxpipe-response-credo.log`, `vxpipe-response-deps.log`). Focused Engine 3/3,
Console 4/4 and Python 61/61 checks pass. No production state-machine transition
changed; this checkpoint does not claim a new Lean run. Full umbrella tests remain
deferred until milestone implementation is complete. No live provider/Telnyx call,
production restart, deployment or pilot activation occurred.

Final GPT-6 Astra xhigh review is clean. Its exact ordinal mutation, real-artifact
positive and interleaved-dispatch controls pass 3/3
(`vxpipe-response-order-fixed-review.log`), and independent Console checks pass
4/4 (`vxpipe-response-order-elixir-fixed-review.log`). Final artifact audit
independently reconstructs response pairs, canonical order, schedule cohorts,
room clocks, p95, ingress/resources/pacing/readiness and cleanup, and verifies all
29 hashes match across corrected phases and current source
(`vxpipe-response-artifacts-review.log`). It confirms the rejected reuse attempt
and outstanding CPU-budget failure are accurately documented. Local documentation
links resolve, and staged whitespace checks pass.
