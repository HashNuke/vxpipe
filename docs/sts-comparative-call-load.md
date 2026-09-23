# Local comparative STS call load

The dedicated lane runs compiled, pinned calls through ordinary room admission,
connection readiness, authorized PCM ingress, room output sinks and public events.
It compares fixture LLM + Morse TTS, Morse STS with provider transcript, and Morse
STS with agent-output STT. Every mode receives the same Morse `HI` input and
generates `RECEIVED HI`. There are no hosted providers or credentials.

## Reproduction

Run from the repository root:

```shell
bin/sts-call-load smoke
# Only in a coordinated quiet window, after integrated review:
bin/sts-call-load measured
```

Smoke uses two simultaneous calls per mode; measured uses ten. Modes run
serially. `CALL_LOAD_JSON` lines contain the machine-readable reports. Preserve
the command, revision, machine details, contention status, exit status and these
lines alongside final evidence. A smoke report is never final performance
evidence. `MIX_DEPS_PATH` may point to already-installed dependency sources; keep
the checkout's own `_build`. The script requires GNU `timeout` and installed
dependencies. It does not fetch dependencies or provision services.

Focused harness tests, from `apps/vxpipe_call_engine`:

```shell
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/speech/call_load_contract_test.exs test/vxpipe/call_engine/speech/call_load_sink_test.exs test/vxpipe/call_engine/speech/call_load_ingress_observer_test.exs
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/speech/call_load_attribution_test.exs
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/speech/call_load_test.exs --only mode:sts_provider --seed 0
```

The tagged lane is excluded by the existing default `:integration` exclusion.
It uses the existing local diagnostic model fixture and embedded connection
fixture. No production runtime modules are modified for the load.

## Workload and meaning

All calls start concurrently, then wait at a readiness barrier before audio.
Each completes one ordinary turn. A second reply is interrupted by a third
microphone utterance after its first output chunk and after the previous input
has finished. The third reply must complete through public events and selected
agent transcript. After every call passes that barrier, one room authority is
killed locally. Its supervised descendants must exit, while each surviving call
completes a fourth input/reply. Healthy rooms are then stopped through their
owning supervisor, with process monitors proving descendant cleanup.

The synthetic output sink incrementally decodes real PCM and discards its bytes.
It accounts for mono PCM duration, including gaps between arriving chunks, and
acknowledges completion only after that duration has elapsed. Interruption returns
only the consumed duration and fences stale timers. This models paced local PCM
consumption; it does not establish physical speaker playback or human hearing.
The stale-timer unit regression injects a controlled clock and captured schedule
tokens with acknowledgement barriers. The runnable smoke/measured lane always
uses the sink's real monotonic clock and actual timer defaults.
Do not interpret these results as hosted model, native transport or browser
capacity. A crashed room authority exercises room-failure isolation, not upstream
provider reconnection.

Nearest-rank p50/p95/p99 reports include sample counts. Missing evidence is `null`,
never an invented zero. Latencies in milliseconds are:

| Metric | Measured interval |
| --- | --- |
| Admission | Public `start_call` invocation to its return |
| Startup | Start invocation through attached connection readiness |
| Input acceptance | Each authorized PCM offer invocation to its result |
| Speech onset | Input producer start to observed public caller turn start |
| Agent speech onset | Input producer start to observed public agent speech start |
| First audio | Input producer start to sink's first received PCM chunk |
| Playback acknowledgement | Input start to sink's elapsed-consumption acknowledgement |
| Turn completion | Input start to observed public agent turn completion |
| Interruption | Barge-in producer start to observed public interruption |
| Failure isolation | Fault injection start through a surviving room's subsequent completion |
| Cleanup | Explicit room stop/fault through monitored descendant exits |

Caller, sink and public turn IDs have separate immutable input-origin bindings.
Input timestamps are captured before feeder creation. Before starting the next
input (including barge-in), the driver waits for the current caller onset, public
agent onset, sink first audio and feeder completion. A sink notification arriving
before a public onset cannot advance the attribution frontier. Late completion
uses its bound origin; duplicate onsets, extra uncorrelated onsets, unknown
completion IDs and wrong room/connection/participant identities fail explicitly.
Public events include
connection-forwarding overhead. Reports also include received/rejected chunks,
chunks discarded by intentional interruption, decoded replies, accepted/rejected
input, ingress drop evidence, final caller/agent transcript counts, and monitored
child counts. Morse STT reports delivered and asynchronously dropped frames via
the configured ingress-owner observer; STS reports its ingress drop counter. An unavailable
counter remains `null` and fails acceptance where drop evidence is required.

Mailbox and process-memory peaks are sampled sums across each room subtree,
connection, sink and call driver. They are sampled observations, not an exact
maximum between observations. Mailbox growth is peak minus post-startup baseline.
No PCM is retained in reports.

## Bounds and acceptance

The script caps ordinary BEAM schedulers at two and at half detected CPUs,
with one dirty CPU scheduler, one dirty I/O scheduler and two async threads.
Each call has at most four input utterances and one outstanding input producer.
Each phase has a 15-second deadline; barriers and task waits are bounded; the
entire command has a 360-second deadline plus a ten-second termination grace.
The sink rejects output beyond one megabyte per turn. The driver aborts above
2,000 sampled queued messages or 128 MB per call, or 1 GB total BEAM memory.
The selected short Morse payload bounds retained samples and decoder state.

The lane fails on missing progress, bad transcripts/decoded output, dropped input,
rejected output, absent measurements, missing interruption, failed healthy calls
or cleanup leaks. Intended interrupted chunks are reported separately from drops.
Investigate a runtime failure before changing the workload to pass it; record a
milestone task before proposing a runtime repair.

Design review: session-allocation conformance was rejected because it bypasses
room policy, readiness, transcripts and playback. Immediate fabricated completion
was rejected because it would hide playback occupancy and interruption costs.
The embedded sink avoids adding native codec/browser workload to this comparison;
those remain separately owned acceptance lanes. A measured ten-call baseline is
recorded below; final milestone acceptance still requires remaining lifecycle
repairs and a coordinated recheck after material runtime changes.

There is no warmup phase. The fixed mode order can include cold module/cache
costs in the first mode's startup; do not attribute that difference solely to
the speech architecture. With ten calls, p99 admission/startup is the maximum
sample, not an estimate of a production tail distribution.

## Measured local recheck — 2026-09-23

The 2026-09-23 post-`d7027d46` egress-queue recheck repeats the measured lane
in a quiet window. All three ten-call modes pass (three tests, zero failures);
each completes 29 turns and ten interruptions, retains nine healthy post-fault
survivors, cleans all ten calls and reports no errors. The run used two BEAM
schedulers on a four-logical-CPU x86_64 host with 7,750 MiB RAM. Exact
`CALL_LOAD_JSON` reports and post-commit gate evidence are in
[`sts-egress-retirement` labnotes](../labnotes/20260923-0059-sts-egress-retirement.md).
This remains synthetic local playback evidence, not remote hearing or hosted
capacity.

## Measured local baseline — 2026-09-22

`bin/sts-call-load measured` at `5792d797bf0439a81dbb8dfc4f960376cdb3659c`
passed all three modes: three tests, zero failures, exit 0, 25.3 seconds. Each
mode held ten concurrent ready calls before input. The parent and parallel
agents had finished their compile/test commands before this run; background
development services remained running. No native or hosted load ran concurrently.

Host: x86-64 AMD EPYC-Genoa, four logical CPUs, 7,750 MiB RAM. Runtime: OTP 28,
Elixir 1.19.5, two ordinary schedulers, one dirty CPU and one dirty I/O scheduler,
two async threads. This is the script's half-machine scheduler profile.

Every mode observed 29 completed turns, ten interruptions, nine healthy
post-fault survivors and ten cleaned calls, with zero reported errors. Each
accepted 2,106 input frames with zero rejected/dropped input and zero rejected
or cleared sink chunks. Intended interrupted chunks were counted separately.

All latency cells below are **p50 / p95 / p99**, in milliseconds, rounded to
three decimals. Counts apply independently to each mode. Definitions and limits
are in the workload section above.

| Metric | Samples | Fixture LLM + TTS | STS provider text | STS + output STT |
| --- | ---: | ---: | ---: | ---: |
| Admission | 10 | 168.500 / 193.118 / 193.118 | 27.101 / 40.306 / 40.306 | 39.896 / 56.873 / 56.873 |
| Startup | 10 | 348.301 / 348.444 / 348.444 | 44.104 / 48.451 / 48.451 | 48.285 / 66.261 / 66.261 |
| Input acceptance | 2106 | 0.115 / 0.310 / 0.423 | 0.163 / 0.320 / 0.450 | 0.141 / 0.372 / 0.556 |
| Caller speech onset | 39 | 5.680 / 21.096 / 21.125 | 4.330 / 9.841 / 14.128 | 3.365 / 12.436 / 12.842 |
| Agent speech onset | 39 | 606.127 / 642.149 / 642.223 | 603.860 / 610.086 / 614.093 | 603.126 / 614.383 / 614.610 |
| First audio | 39 | 594.000 / 634.650 / 634.652 | 588.567 / 594.785 / 594.794 | 585.292 / 588.407 / 589.277 |
| Playback acknowledgement | 29 | 2592.682 / 2638.611 / 2638.625 | 2489.567 / 2495.785 / 2495.794 | 2487.241 / 2489.407 / 2490.277 |
| Turn completion | 29 | 2595.924 / 2650.209 / 2650.220 | 2493.912 / 2504.339 / 2504.430 | 2488.304 / 2493.115 / 2493.220 |
| Interruption | 10 | 5.896 / 12.251 / 12.251 | 5.621 / 16.628 / 16.628 | 9.056 / 14.687 / 14.687 |
| Failure isolation | 9 | 2599.643 / 2602.742 / 2602.742 | 2495.733 / 2499.569 / 2499.569 | 2493.393 / 2495.512 / 2495.512 |
| Cleanup | 10 | 3.835 / 4.608 / 4.608 | 2.094 / 4.013 / 4.013 | 0.929 / 2.333 / 2.333 |

| Bounded observation | Fixture LLM + TTS | STS provider text | STS + output STT |
| --- | ---: | ---: | ---: |
| Mode elapsed, ms | 8863.053 | 8166.404 | 8157.837 |
| Largest sampled per-call mailbox / growth | 5 / 5 | 6 / 6 | 9 / 9 |
| Largest sampled per-call process memory, bytes | 1788024 | 1316488 | 1571040 |
| Descendants monitored through cleanup | 470 | 290 | 390 |
| Intentionally interrupted chunks | 8 | 377 | 299 |

The fixed mode order has no warmup, so startup differences include cold
module/cache effects. First PCM arrival and public speech onset use different
observation paths; their relative order is not a causality claim. Morse PCM
duration dominates completion time. These results do not establish hosted-model
latency, carrier/browser transport capacity, physical hearing, billing accuracy
or safety of the still-open lifecycle cases. Repeat this lane after material
runtime changes during final milestone acceptance. The complete machine-readable
`CALL_LOAD_JSON` output is in temporary log `vxpipe-sts-load-measured.log`;
[checkpoint labnotes](../labnotes/20260922-1657-sts-ten-call-measurement.md)
record coordination and scope.
