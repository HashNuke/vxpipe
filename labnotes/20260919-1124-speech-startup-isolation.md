# Speech startup isolation and latency evidence

> Relocated from `docs/speech-startup-isolation.md` on 2026-10-09. First recorded source commit: `4cfaa5280722` (2026-09-19T18:24:00+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260919-1624-speech-startup-isolation](20260919-1624-speech-startup-isolation.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [simpler-speech-integrations](milestones/simpler-speech-integrations.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Status: baseline recorded before continuing checkpoint R on 2026-09-19; zero of nine
checkpoints accepted. The user requires test evidence before treating a design concern as a
stability defect. This document records that evidence; it does not approve the current session
implementation.

The subsequent [ownership replan](../docs/speech-session-ownership.md) proposes room-scoped speech
trees, asynchronous local initialization and admission-time deadlines. The historical
measurements below remain unchanged; the proposed fix has not been implemented or verified.

## Finding and decision

The new standalone semantic session boundary introduces cross-session startup blocking.
A held provider initialization delays unrelated healthy Morse sessions beyond their
configured startup budget. Existing per-room startup and replacement connectors do not
show that coupling in the same controlled scenario. Keep the current room path intact and
room migration pending until this regression test is green.

This is a demonstrated availability/isolation defect in the proposed boundary. It is
not evidence that existing calls currently lose audio, interrupt active recognition or
crash. The new boundary has not been connected to rooms. All diagnostic changes here are
tests, a benchmark and documentation; this investigation makes no runtime fix or rollback.

## Controlled reproduction

The [isolation test](../apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/startup_isolation_test.exs)
starts isolated supervised process trees, without creating calls or contacting services.

1. A probe acknowledges that it is held inside bounded provider initialization.
2. Eight unrelated real Morse STT sessions each request a 100 ms startup budget.
3. After a 300 ms observation window, the test explicitly releases the held provider.
4. All eight sessions then start and decode independently generated PCM as `E`.

| Case | Observed result |
| --- | --- |
| New sessions, no held peer | Eight startups took 6–7 ms in seed 0; 1–2 ms in seed 42. |
| New sessions, held peer | Zero of eight completed before release; `Session.start/1` took 301–302 ms in seeds 0 and 42, despite each 100 ms budget. |
| Existing initial STT, separate room-incarnation supervisors | Healthy Morse reached readiness and final `E` while the other initialization remained held. |
| Existing replacement/preparation connector | Healthy Morse reached readiness and final `E` while another connection remained held. |

The failing assertion checks startup-call duration, not decoding duration. Successful
recognition after release rules out malformed configuration or PCM as the cause.
The explicit hold/release establishes the dependency; this is not a generic test of OTP
serialization. Tests run serially because the new supervisor is shared. The short timing
budgets can be noisy on an overloaded host, so both controls and release-dependent recovery
are part of the evidence.

The mechanism is visible in the proposed implementation: `Speech.Session.start/1` calls
the one shared `Speech.SessionSupervisor`, which waits for `SessionTree.start_link/1` and
provider initialization. The absolute startup deadline is created only when that queued
request begins executing. Queue wait therefore is not part of its budget. The compared
existing RoomCapabilitySupervisor, TransportConnector and Morse transport files have no
worktree changes.

## Active recognition under load

The opt-in [latency benchmark](../apps/vxpipe_call_engine/bench/speech_latency.exs) compares
the existing Morse capability with the new semantic facade. Each owner has its own provider
and performs one turn at a time. Trials use 1, 8 and 32 concurrent owners, 10 warmup rounds,
200 measured rounds and three repeats with alternating path order. A barrier releases each
round outside the measured interval. Normal and held-startup scenarios at 32 semantic
owners are interleaved with alternating order.

Each turn uses independently generated raw mono 16 kHz linear16 PCM: a 60 ms dot and an
840 ms end gap, representing `E`. Input is split into dot plus three gap units (7,680 bytes)
and the remaining eleven gap units (21,120 bytes). Input is unpaced: these are synchronized
bursts measuring processing after bytes arrive, not 900 ms of real-time playback or human
speech endpoint latency.

Measurements use a monotonic clock:

- Audio admission: public push-call completion, separately sampled for both chunk sizes and
  pooled in the reported distribution; it includes decoding work performed during the call.
- Speech start and first transcript: prefix submission to consumer-usable semantic events.
  The new path must successfully acknowledge each event before its timestamp is recorded.
- Turn end: final-gap submission to the consumer-usable turn-ended event.
- Total turn processing: prefix submission to turn end. Startup through observed readiness is
  recorded separately, before fixture construction and the per-turn workload.

Every measured turn asserts the expected event order and exact transcript `E`. There were
**68,400 successful measured turns**, with no recognition timeout or incorrect transcript.
The already-ready/held-startup scenario accounts for 19,200 of them. A provider monitor
verifies that the held initialization did not time out before its explicit release.

Canonical run: Elixir 1.19.5, OTP 28, eight online schedulers; 7.5 seconds of test execution.
All latency values below are milliseconds, rounded to three decimal places.

| Path | Owners | Measured turns | Audio admission p95 | First transcript p95 / p99 | Turn end p95 / p99 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Existing | 1 | 600 | 0.262 | 0.171 / 0.334 | 0.292 / 0.470 |
| Semantic | 1 | 600 | 0.302 | 0.205 / 0.383 | 0.350 / 0.549 |
| Existing | 8 | 4,800 | 0.494 | 0.494 / 1.025 | 0.504 / 0.912 |
| Semantic | 8 | 4,800 | 0.548 | 0.657 / 1.079 | 0.524 / 0.962 |
| Existing | 32 | 19,200 | 1.867 | 2.195 / 4.793 | 1.523 / 3.554 |
| Semantic | 32 | 19,200 | 2.492 | 3.485 / 7.033 | 2.105 / 5.257 |
| Already-ready semantic, another startup held | 32 | 19,200 | 1.771 | 2.427 / 4.718 | 1.509 / 2.800 |

The [machine-readable report](20260919-1624-speech-latency-metrics.json) includes
p50/p95/p99/maximum, sample counts, startup readiness and every trial's distributions.
At 32 owners, maximum first-text/turn-end latency was 67.746/63.858 ms on the existing
path and 28.855/20.616 ms on the semantic path. Single maxima and lower held-startup
percentiles must not be interpreted as a causal performance improvement.

All three normal semantic 32-owner repeats had higher first-text and turn-end p95 than
their existing-path counterparts. That is measured overhead in this workload, separate
from the startup isolation failure. No latency SLO was supplied, so it is not an asserted
SLO violation. Repeated turns are correlated within just three trials; they are not
68,400 independent experiments. Startup has only three samples at one owner, including
cold-start effects, so its p99 is effectively the maximum.

These are different public boundaries before room migration: the old capability includes
projection/policy processing, and the new facade is not yet embedded there. This is a useful
baseline, not a prediction of final room performance or a sustained capacity limit. No
hosted STT, TTS output, audio playback, network loss or browser latency was measured.

## Next decision and alternatives

Before resuming migration, choose startup ownership that keeps slow initialization off a
supervisor shared by unrelated calls. Candidate directions are immediate subtree admission
with owned asynchronous initialization, or suitably scoped owning supervisors. Preserve
owner-loss cleanup, bounded private initialization, generation fencing and existing privacy
intervals; simply making startup asynchronous is insufficient if cancellation can orphan it.
Start the absolute deadline at API admission and include queue wait.

Increasing the timeout is rejected as a solution: it retains the demonstrated coupling.
Excluding queue wait from the deadline is also rejected. A broad rollback is not currently
necessary to restore call behavior because the original room path remains in use, and no
checkpoint has been committed. No architecture fix is implemented by this document.

## Reproduction and acceptance evidence

From `apps/vxpipe_call_engine`:

```shell
# Expected to fail until startup isolation is fixed:
mix test test/vxpipe/call_engine/speech/startup_isolation_test.exs --seed 42

# Existing controls and other checkpoint tests; deliberately excludes the known red test:
mix test test/vxpipe/call_engine/speech/startup_isolation_test.exs test/vxpipe/call_engine/speech/stt_session_test.exs test/vxpipe/call_engine/provider/morse_code --exclude startup_isolation_regression --seed 21

# Opt-in local burst benchmark, outside default test discovery:
MIX_ENV=test mix run bench/speech_latency.exs /tmp/vxpipe-speech-latency.json
```

The full selected suite at seed 42 produced **39 tests, one failure**, the intended startup
regression. Excluding it produced **38 tests, zero failures, one excluded** at seed 21.
The benchmark produced **one test, zero failures** with 68,400 measured turns. An earlier
broader run exposed a test-only timer race: either the OTP startup timeout or channel timer
can win. Its assertion now checks safe startup failure, monitored teardown and withheld early
readiness, rather than requiring the optional channel timeout message. Runtime behavior was
not changed during this investigation.

GPT-6 Astra xhigh independently reviewed the test causality, cleanup, methodology and final
report. The review found no evidence blocker and required the scope limitations above.
The milestone remains at zero completed checkpoints; full umbrella acceptance has not passed.
