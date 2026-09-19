# Native STT contract and verification

Checkpoint A completes the standalone STT boundary on top of R's scoped lifetime
and deadline handling. Production rooms continue to use legacy speech until the
native TTS gate D and room migration B. R and A are accepted: two of nine speech
checkpoints are complete.

## Decisions

`Descriptor.new/1` validates a closed set of STT metadata. The engine validates
again before starting a provider, including directly constructed structs.
Formats distinguish raw mono PCM16 from raw mono Opus; providers still validate
their supported sample rates and settings. Morse remains raw mono PCM16 at 8,
16, 24 or 48 kHz, with no new codec or resampling. Descriptor inspection omits
settings and usage identity. Credentials and I/O remain private startup concerns.

Readiness and endpointing events must match the descriptor. Speech-start,
eager-end and resumed-turn evidence require their advertised support flags.
Eager-end support requires provider-owned endpointing; a descriptor promising an
event that cannot carry valid evidence is rejected. Native names remain
`speech_started` and `transcript`; legacy room signal names remain unchanged.
Optional provider request IDs are nil or 1..256 valid UTF-8 bytes and are hidden
from inspection. A new local event sequence cannot deduplicate upstream repeats;
provider adapters retain that responsibility.

Input has one outstanding command, one persistent allocation-local worker and
the existing 1..131,072-byte limit. Its deadline starts at API entry; raw bytes
cannot establish microphone capture age. B must retain existing ingress age
checks. Duplicate dispatch, stale worker completion and old timers cannot claim
or release newer input. An old allocation's event cannot consume a replacement's
readiness credit.

Provider `:ok` means the chunk reached a bounded provider/transport acceptance
slot. Processing can complete later. `{:error, :busy}` means this chunk was not
accepted and the session remains usable. Other unexpected results still retire
the allocation with a fixed safe error. No automatic retry or replay is added.
The consumer can use this acceptance with the existing STT usage accumulator:
one start, retained evidence after later processing failure, one terminal
settlement, and no invented text or duration measurements. A controlled deferred
provider proves this boundary; production room attribution/projection stays in B.

Rejected alternatives were constructor-only validation, accepting contradictory
metadata, treating every provider rejection as fatal, and adding an extra
per-chunk usage event despite an existing synchronous acceptance boundary.
None requires new provider accounts, a transport behaviour or a global worker.

The user accepts about 1 ms of processing overhead for reliability. Acceptance
does not require an overall speedup. Tail spikes, deadlines, lost/stale output,
queue growth and cleanup remain separate stability checks.

## Focused verification

Descriptor regressions first demonstrated missing validation, malformed metadata
starting a provider, mismatched readiness activating a session and unsupported
events being admitted. Request-ID tests first demonstrated empty/invalid UTF-8
acceptance and missing eager/resume forms. The deferred provider tests reproduced
busy rejection killing the allocation; preserving only the known `:busy` category
allows existing work to finish and another explicit chunk to be accepted.

The existing tests retain independent PCM expectations, odd chunk boundaries,
malformed/oversized input, exact acknowledgements, overflow, safe errors,
owner/provider teardown, deadline races and redacted status/crash reporting.
The [README example](../apps/vxpipe_call_engine/README.md#standalone-semantic-morse-recognition)
uses an independently generated dot and gap for expected `E`.

The final focused group passed **103 tests** (82 speech cases plus existing Morse
and STT usage cases; seed 293622). The README example ran verbatim. GPT-6 Astra
xhigh reviewed the contract, input/usage tests and stale-work fencing. Its final
descriptor finding was reproduced red and fixed; no A code blocker remained,
conditional on completed acceptance and accurate evidence.

## Load verification

Apple M2, eight cores, 16 GiB RAM; Elixir 1.19.5, OTP 28, eight online schedulers.
The unchanged harnesses run from `apps/vxpipe_call_engine`:

```shell
MIX_ENV=test mix run bench/speech_latency.exs /tmp/speech-latency.json
MIX_ENV=test mix run bench/speech_faults.exs /tmp/speech-faults.json
MIX_ENV=test mix run bench/speech_adoption.exs /tmp/speech-adoption.json
```

Two latency runs each passed **68,400 measured turns**, with the same independent
`E` PCM fixture, legacy baseline, alternating three repeats and 1/8/32 concurrency.
The second run's 32-owner p95/p99 values, in milliseconds:

| Delivery metric | Legacy p95 / p99 | Native p95 / p99 | Native with held startup p95 / p99 |
| --- | ---: | ---: | ---: |
| Audio acceptance | 1.490 / 2.273 | 1.794 / 3.135 | 1.578 / 2.594 |
| First text | 1.677 / 2.527 | 2.565 / 4.075 | 2.225 / 3.474 |
| Turn end | 1.246 / 1.917 | 1.531 / 2.491 | 1.460 / 2.234 |

The added p95 first-text/end latency was 0.888/0.285 ms in this run, within the
user's stated reliability tradeoff. This compares the current native and legacy
paths, not the causal cost of A alone. No speedup or concurrency ceiling is claimed.

The first run's held-start repeat 2 had maximum first-text/end delays of
99.701/97.866 ms. The full follow-up did not repeat them: held-start maxima were
12.928/5.067 ms, and ordinary legacy maxima were 13.268/12.779 ms. All expected
events arrived in both runs. Their cause is unestablished; the outlier remains
recorded instead of being attributed to the architecture or hidden by percentiles.
[First run](../labnotes/20260919-2013-speech-latency.json),
[final-source follow-up](../labnotes/20260919-2013-speech-latency-repeat.json).

The final concurrent-fault run passed **72 trials and 39,360 healthy turns**.
Eight fault types independently exercise provider, channel, input, provider
supervisor, initializer supervisor, capability control, admission and session
supervisor loss. Healthy peers continue while failure handling and explicit
replacement run in another task. At 32 healthy allocations, the largest observed
safe-observation/teardown/replacement-ready timings across all fault types were
2.479/2.481/4.552 ms. At one healthy peer, one teardown reached 29.028 ms; its safe
observation still arrived within 0.214 ms. These are distinct boundaries.
Allocation failures use a safe closed event; shared failures use capability DOWN.

Every 8/32-peer trial recorded actual processing intervals overlapping replacement;
the minimum counts were 6/15. At one peer the minimum was zero, so not every trial
proves simultaneous processing at that concurrency. Process count returned to
245 after every trial; memory ranged from 80.5 to 86.2 MB. Owned descendants
terminated and exact healthy text, allocation and event-kind checks passed.
This fault harness does not compare turn references. Temporary sessions
do not reconnect or replay; a replacement starts only when explicitly requested.
[Final fault report](../labnotes/20260919-2013-speech-faults-final.json).

The final adoption run passed **36 trials and 16,236 measured turns** in alternating
direct/adopted modes at 1/8/32 scopes. It checks exact content, order, generation,
old-lease rejection, current-consumer close and descendant termination. Burst
trials have 30 measured rounds; paced trials have three, with 20 ms waits after
completed pushes plus processing. Active input pauses during candidate churn,
so this is not a continuous real-time call simulation.

At 32 scopes, healthy first-text/end p95 was 4.238/2.762 ms for adopted burst
candidates and 1.438/0.815 ms paced. The direct controls were 6.173/3.159 ms burst
and 2.762/0.626 ms paced. Adopted close p95 was 2.291/0.802 ms; obsolete-lease
rejection was 0.414/0.205 ms. Burst tails were higher than the preceding run in
both modes; the report retains each repeat and maxima. No content, identity,
authority, deadline or cleanup assertion failed. Process count returned to 245
in every trial, with memory 85.5–89.3 MB.
[Final adoption report](../labnotes/20260919-2013-speech-adoption-final.json).

The final three diagnostics therefore cover **123,996 measured turns**. Earlier
passing fault/adoption runs remain recorded in the labnote; one short descriptor
test overlapped the preliminary adoption run, so its timing is not used as the
final reference. The final diagnostics ran serially before the umbrella suite.

All five root gates passed: formatting, warning-free compilation, strict Credo,
the complete umbrella suite (**1,880 tests, zero failures, 40 excluded; seed 330044**)
and the unused-lock check. An earlier root run exposed a safe-failure-category race
in a new test; a focused rerun exposed an implicit 100 ms notification wait. The
reviewed test corrections retain runtime deadlines and stale/closed assertions.
The full same-seed rerun passed, including all 782 Call Engine tests. The
[checkpoint labnote](../labnotes/20260919-2013-native-stt-contract.md) records all
runs and limitations; the [milestone](milestones/simpler-speech-integrations.md)
remains the acceptance checklist. Isolated local STT tests do not establish
hosted/network interoperability, full call capacity or TTS playback performance.
