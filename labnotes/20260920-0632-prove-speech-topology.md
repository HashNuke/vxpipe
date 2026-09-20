# Prove speech topology

## Scope

Build the proposed merged Channel/Output state as a test-only isolated process tree
and compare it with a faithful split reference before touching production runtime
source. Preserve actual authorization, absolute deadlines, event acknowledgements,
incremental PCM credit, watchdog teardown, pending-Input cancellation, replacement,
independent STT and input-fact retention.

## Red-green history

- The first contract revision failed both topology cases because the constant-PCM
  prototype had no ready event or event acknowledgement API. It also exposed that
  the prior split audio acknowledgement incorrectly proxied through Channel.
- Implemented real Morse Encoder/Decoder use, authorized consumer calls, exact event
  acknowledgement, fixed fence deadlines, queued cancellation, one outstanding
  credit and direct split Output acknowledgement. Two topology cases passed.
- Added deterministic credit and abandoned-fence watchdog checks. Both abandoned
  fence cases failed because expiry only stopped the tree when a cancel caller was
  waiting. Changed expiry to stop the disposable tree with or without a waiter.
- Final focused result: 4 tests, zero failures, seed 530504.

## Benchmark corrections

The first four prepared JSON reports used one constant PCM chunk, echo STT and an
extra split Channel-to-Output acknowledgement hop. Astra review identified those
limits. Retain the reports as preliminary evidence only; they do not prove the
native-call claim. Prepared run 1 also failed the old one-millisecond relative
diagnostic in five aggregate metrics.

The corrected benchmark:

- uses the production Morse Encoder incrementally at 20 ms chunks;
- decodes independently generated PCM through the production Morse Decoder;
- makes every public operation through the exact consumer process;
- acknowledges ready, submitted, cancelled and completed events exactly;
- carries API-entry/fence deadlines without refresh;
- routes split audio acknowledgement directly to Output;
- fires credit and cancellation watchdogs in focused tests;
- verifies the first E chunk and complete T output against exact PCM, checks
  request/provider/audio correlation, input facts and unexpected terminal/audio
  absence, and checks empty allocation supervisors after every trial;
- reports the one-millisecond 32-scope comparison without using it as a gate;
- checks every concurrency point and requires merged to pass whenever split passes;
  the first fixed p99 miss remains a nonmonotonic diagnostic.

An initial full run completed but used an incorrect relative output path and could
not write its report. It is not evidence. Native run 1 then exposed a weak gate:
split passed at 64 scopes while merged replacement-first-audio p99 was 19.482 ms.
The first-miss-only assertion still passed. Retain that report as a failed
pointwise result. Strengthened the assertion, added exact audio validation,
playback ceilings, bounded provider IDs and deadline settlement checks, then ran
three fresh decision reports.

## Evidence

Machine: Apple M2, 16 GiB RAM, eight logical CPUs/schedulers, Elixir 1.19.5,
OTP 28. Each report contains three alternating repeats, eight workflows per scope
and concurrency 1/8/32/64/128/256.

All three final-source reports pass pointwise and first-miss gates with 70,416
complete workflows:

| Report | Split first fixed-gate miss | Merged first fixed-gate miss |
| --- | ---: | ---: |
| native-4 | 64 | 128 |
| native-5 | 32 | 128 |
| native-6 | 128 | 128 |

Every pointwise-violation list is empty. Absolute first-miss locations vary and
are not capacity knees. At 32 scopes merged passes every budget in all three
decision runs; split first-audio p99 reaches 20.301 ms in run 5. Keep the
variability visible; the result does not prove every run or metric is faster.

At 256 scopes, sampled peak process counts are 2,744-2,764 split and
2,416-2,508 merged. Memory is lower for merged twice and 6.327 MB higher once.
Claim the process reduction, not deterministic memory reduction.

GPT-6 Astra xhigh independently recalculated the reports, confirmed topology
parity and the pointwise predicate, and found no blocker to the narrow D0
feasibility gate. It noted that injected watchdog messages prove teardown handling,
not adversarial elapsed-deadline races; retain production deadline tests during
migration.

Durable reports:

- labnotes/20260920-0632-tts-topology-native-4.json
- labnotes/20260920-0632-tts-topology-native-5.json
- labnotes/20260920-0632-tts-topology-native-6.json

## Decision

Retain the merged owner as the implementation candidate. The isolated
Morse test adapters passed every concurrency where split passed in three final
runs and preserved the selected reliability workflow with one fewer allocation
process.

Do not call this production proof. Channel/owner code is test-only, and the workload
omits generation adoption, full usage accounting, room policy, physical playback,
codec/network and hosted providers. Runtime D remains paused and its original
pending-Input regression remains red. The next vertical slice must implement the
same workflow in production, rerun that original failure, then repeat fixed-gate
load and full acceptance checks.

## Final verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict` and `mix deps.unlock --check-unused` pass from the umbrella
  root.
- The focused topology test passes: 4 tests, zero failures, seed 530504.
- The production admission/cancellation reproduction remains red: 2 tests, one
  failure, seed 530504. This is the pre-existing runtime blocker.
- A full umbrella test run at seed 221234 completed Call Engine with 807 tests and
  two failures before the later Gateway run was stopped. One is the known
  cancellation failure. The other startup-deadline lifecycle case received
  `startup_timeout` instead of `ready` under suite load; it then passed alone and
  the complete 23-test lifecycle file passed with the same seed. Record this as a
  current contention-sensitive observation, not as instability caused by the
  test-only topology experiment.
