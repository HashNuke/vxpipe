# External configured diagnostic workload

## Scope and contracts

Add a bounded smoke workload using the configured Console/Calls/room-service/STT
and diagnostic persistence path with real pinned Silero inference. It runs all
four operational-VAD/collection combinations. This is a prerequisite to the full
fresh-VM paired measurement matrix, not performance acceptance: it currently uses
one human input, two turns and 64 frames (2.048 seconds) per case. Multi-input room
topologies, warm/cold phases, response/egress latency samples and complete resource
report integration remain outstanding.

A separate Python process drives 512-sample 16 kHz frames over the local port's
length-framed pipe. Its absolute 32 ms schedule never waits for provider receipts.
The reusable generator supports 1–16 staggered inputs and at most 1000 frames per
input. It repeats the existing synthetic PCM fixture without padding/truncating
samples, records its hash and every write-completion lateness, and rejects timing
when nearest-rank p95 exceeds the predeclared 2 ms limit. Pipe blocking counts as
lateness. Generator CPU is reported separately from the measured BEAM process.

The configured loop accepts frames independently of provider acknowledgements,
checks complete exact PCM delivery and uses provider receipts to order the two
scripted settlements. This preserves input/provider causality without pacing the
external generator. The existing full public control-trace oracle checks both
turns after teardown. Enabled cases require two durable canonical timing rows;
disabled cases require none. Actual classifier callbacks wrap `Silero.push`, never
replace probabilities; operational reuse must not execute fallback inference.
With both flags off there must be no inference or model-load attempt.

The new cases are explicitly integration-tagged and selected with `--only
external_pcm`. No real provider connection, Telnyx number or service change.

## Red-green evidence

Generator contracts were written before the implementation: missing-module red,
then 4/4 green for absolute staggered scheduling, blocked-pipe lateness, exact PCM
wrapping and invalid workload rejection.

Configured smoke was written before adding the actual-inference fixture option.
Its initial selection produced 4 cases / 3 failures: the three inference modes
failed specifically waiting for actual-inference evidence, while the all-off
control passed. That initial command was accidentally issued from the umbrella;
it skipped unrelated child paths and executed only the matching Console file.
Subsequent configured commands run from the owning Console child or its watchdog.

## Invalid attempts and CPU isolation correction

Preserved attempts, all with the original 2 ms timing limit and no watchdog abort:

| Attempt | Result | Invalid generator p95 values |
| --- | --- | --- |
| Inherited taskset, sleep pacing | 3/4 | 2.273 ms fallback/on |
| Separate generator affinity, sleep pacing | 1/4 | 2.644 / 2.466 / 3.987 ms |
| Separate affinity, bounded 2 ms spin guard | 3/4 | 2.341 ms reuse/on |
| Same guard with wake/write breakdown | 2/4 | 2.242 ms reuse/off; 2.079 ms reuse/on |

The breakdown records aligned pre-write lateness and wall time around packet
construction/write, in addition to final completion lateness. It does not uniquely
distinguish OS preemption from pipe blocking. A standalone memory-sink diagnostic
with 125 frames at 2/8/32 ms spin guards had p95 below 0.019 ms in all three cases;
there was no basis to increase the production guard, which remains 2 ms.

Inspection found the concrete isolation flaw: after `taskset -c 0,1`, loading the
pinned Silero model created 11 threads allowed on 0–1, and three native workers
respectively pinned to 1, 2 and 3. ONNX Runtime overrode inherited affinity and
competed with the supposed external generator CPUs. Therefore earlier attempts
cannot qualify as two-CPU performance measurements even when their pacing passed.
Their functional/negative-control evidence remains valid within its stated scope.

A transient system scope with `AllowedCPUs=0,1`, running the command as the normal
checkout user, enforced masks 0–1 or 1 for all 14 threads. The user manager has no
cpuset delegation on this host. No production unit, provider setting or native
model configuration changed. Tooling PATH/MIX_HOME/HEX_HOME/runtime-directory
values must be retained for the ordinary-user command; an initial isolated loader
probe without MIX_HOME did not find Hex and did not execute the workload.

A direct Port generator inherited the strict cgroup and correctly failed to set
CPUs 2–3: all four cases failed at its nonzero exit. The new optional
`VXPIPE_DIAGNOSTIC_GENERATOR_SYSTEMD=1` launch instead asks the user manager to
start the generator outside the measured scope, with `--pipe --wait --collect`.
`VXPIPE_DIAGNOSTIC_GENERATOR_CPUS=2,3` pins and reports its actual mask. The generated
service has a 45-second lifetime and two-second stop timeout. Each test gives it
a unique owned name and requests stop during on-exit cleanup. It preserves the
same binary framing and external clock; the BEAM never paces the generator.

## Review findings and controls

- A repeat-first-frame mutation initially passed all six generator tests because
  the test PCM repeated on 1024-byte boundaries. Root reproduced that false pass.
  A nonperiodic fixture now rejects the mutation at the exact wrap assertion;
  the other controls pass. Exact requested affinity is checked after applying it.
- Operational warm-up alone originally satisfied the native-inference assertion.
  An independent configured control ran one native silent warmup and bypassed
  all 64 generated frames, yet passed. Evidence now includes the classified PCM
  fingerprint and must match generated non-silent audio; it cannot be warmup-only.
- A post-loop extra provider PCM message originally escaped the oracle. A control
  reproduced the false pass. The test now monitors complete room teardown, drains
  diagnostic resources and rejects any remaining provider delivery before success.

Root regenerated both configured fault controls against the fixed code: both fail
exactly at the strengthened oracle, with valid timing (p95 0.054 / 0.645 ms).
A fourth lifecycle finding followed the ownership change: stopping the Port client
did not terminate a SIGSTOPed user-manager producer, whose runtime limit was
initially infinite. The review probe reproduced the retained active service.
The fixed launch applies RuntimeMaxSec=45 and TimeoutStopSec=2 and stops its
exact UUID-named unit on test exit. The same probe verifies those properties and
complete producer termination/inactive unit after cleanup. If the VM/watchdog dies
before on-exit cleanup, the service's bounded lifetime is the fallback; the future
reusable watchdog should additionally stop its recorded owned units on abort.

Generator timing/affinity/spin/breakdown contracts were added red-first; the complete
Python helper selection now passes 16/16. No acceptance limit was relaxed.

## Enforced-isolation smoke result

Initial enforced-cpuset run: 4/4 pass, seed 0, 23.1 seconds. The final rerun after
bounded named-service cleanup also passes 4/4, seed 0, 23.1 seconds. Each has 64 exact provider frames,
two complete public turn traces, no extra commits/delivery, correct real-model mode,
and either two durable input rows or no diagnostic rows according to the setting.
Native evidence proves generated non-silent PCM was processed, not full-frame
coverage; the 99% warm coverage gate remains part of the full measurement driver.

| Operational VAD | Collection | Generator p95 lateness ms | Generator CPU seconds |
| --- | --- | ---: | ---: |
| Off | Off | 0.055204 | 0.122520 |
| Off | On | 0.052718 | 0.120106 |
| On | Off | 0.210017 | 0.118761 |
| On | On | 0.044019 | 0.116859 |

The external watchdog sampled 261 times, observed peak VM RSS 744764 KiB and
minimum available host memory 2696300 KiB, and confirmed every observed native
thread mask was 0–1 or 1. No abort against the 1024 MiB RSS / 768 MiB available
limits. The pinned model loader checks its existing SHA256; PCM fixture hash is
`f64f9c4da451394ad3a3ff717c28a96dd0d7ddf291a182e5e3a4492e9173fe3c`.
Raw generator reports, invalid attempts and watchdog samples are retained in local
temporary `vxpipe-diagnostic-external-*` artifacts, including the final `bounded`
log/JSON and its runner. This does not replace the reusable full measurement runner.

The existing four synthetic inference-mode cases and actual pending/late timing
case also pass 5/5, seed 514564, 27.4 seconds, after the fixture setup changes.
Final format, warnings-as-errors compile, strict Credo and unused-lock checks
pass. Independent Astra xhigh source/design/documentation review is clean after
the four reproduced proof/lifecycle fixes. Full paired performance, accuracy and
live acceptance remain open; no deployment.
