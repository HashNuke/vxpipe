# Scoped speech deadlines and failure containment

This completes the next ownership work after the [adoption authority repair](speech-adoption-fix.md).
The implementation remains isolated from production room speech consumers. Checkpoint R's
final review and umbrella acceptance are recorded in the [milestone](milestones/simpler-speech-integrations.md).

## Decision

Each capability has a responsive lifecycle controller, a persistent admission worker and a
local allocation supervisor. Each allocation owns its Channel, one persistent input worker,
provider supervisor and initialization Task supervisor. Tasks are used for initialization;
audio chunks no longer create Tasks. All these execution children are temporary and significant.
Allocation child failure retires that allocation. Shared controller/admission/session-supervisor
failure retires the capability. Other scopes retain their own execution trees.

ScopeControl reserves at most two slots and dispatches admission asynchronously. A cancelled
queued admission retains its slot until the worker acknowledges completion; repeated close/start
cannot accumulate an unbounded admission backlog. Private initialization remains only in the
controller until the provider handoff, and is removed on handoff, cancellation or expiry.
Retained supervision arguments contain opaque allocation identity and public configuration.

The alternative of calling Task.Supervisor and then bounding Task.yield was rejected: Task
creation itself can wait indefinitely before yield begins. Moving that call into ScopeControl
would block cancellation and expiry. The persistent workers keep those waits outside lifecycle
control and bring forward the minimal worker foundation previously scheduled for A4. A4's
remaining input, usage, envelope and latency acceptance is still required.

## Deadline and completion contracts

Startup mints one absolute allocation deadline before reservation. Activation settles it.
Later calls use independent API-entry deadlines; `call_timeout` must be 1–5,000 ms, default
5,000. Startup accepts a positive finite millisecond budget, with the public reservation wait
still capped at five seconds. Internal queue waits consume the existing budget.

Input accepts one exact current-consumer/handle/ticket/deadline combination. Channel dispatches
by cast; the worker claims that ticket and rechecks time before calling the provider. Channel
rechecks time on completion. `:ok` means the provider callback accepted the chunk, not merely
that it entered a mailbox. Unknown callback results and exceptions become a fixed safe failure.
An expired queued request returns `:command_timeout` without closing a usable allocation.
An admitted timeout fences the allocation before returning `:session_failed`, kills owned work,
and cannot replay the chunk. Physical DOWN may follow the bounded failure result.

Adoption uses an atomic commit/abandon ticket through API, Channel and ScopeControl. An
uncommitted timeout prevents later activation and allows a fresh attempt before the original
startup deadline. A timeout after commit retires the uncertain allocation; it never silently
leaves controller and Channel with different authority. Channel checks the deadline again before
ready delivery, including direct startup. Old-lease close remains rejected after valid adoption.

Close authorizes cancellation against the current controller record and obtains the actual
owned tree there, including a tree created while admission is handing it off. The caller awaits
that tree's DOWN using the remaining original budget. A close queued past its deadline reports
`:close_timeout` and cannot execute later. A committed cancellation whose teardown misses the
budget also reports timeout; it does not claim cleanup finished. Closing work that has not yet
created a tree atomically prevents subsequent provider admission.

## Focused verification

The deadline tests first reproduced held-control close and input-cleanup waits, expired Channel
input admission, blocked startup admission, delayed adoption, invalid budgets, and unsafe provider
returns. Two deterministic debug barriers additionally reproduced late ready delivery after an
adoption timeout and false close success during tree creation. Their corrected assertions and the
existing speech behavior suite pass (70 tests); a separate direct-start test covers a late activation reply.
Malformed owner/consumer/lease combinations reject before reservation, preserving active siblings.
A public reservation timeout invalidates queued work before resumed control can retain private data
or create a provider.

The lifecycle suite checks queued cancel/expiry, owner/lease/consumer loss, stale handles,
unchanged parentage after adoption, startup deadline settlement, private handoff/redaction,
bounded admission slots, actual supervisor ancestry, and allocation/shared failure boundaries.
Healthy siblings and explicitly created replacements decode independently generated `E` PCM.
The tests monitor exact descendant termination; Registry may briefly retain those already-dead
PIDs, which is not evidence of an orphan or a restarted child.

## Fault load experiment

Run from `apps/vxpipe_call_engine`:

```shell
MIX_ENV=test mix run bench/speech_faults.exs /tmp/speech-faults.json
```

On Apple M2, 8 cores, 16 GiB RAM, 8 online BEAM schedulers, **72 trials and 39,360 healthy
Morse turns passed**. Three repeats used 1, 8 and 32 healthy peers plus a failed allocation.
Eight failure types covered provider, Channel, input worker, provider supervisor, initializer
supervisor, shared control, admission worker and shared session supervisor. Each trial ran 40
turns per healthy peer. After first text in round 20, the coordinator released healthy end-gap
input and an independent fault task. Healthy rounds continued while that task observed teardown,
explicitly created a replacement, waited for ready, decoded `E`, and closed it. Monotonic input-processing
intervals overlapped replacement startup in every 8-peer trial (at least two intervals) and
32-peer trial (at least 15). Some single-peer replacements fell between chunks; those trials do
not prove simultaneous processing during replacement. An interval spans submission through acknowledged
semantic event completion; it is broader than time inside `push_audio`. No automatic reconnect, restart or replay is implied.

At 32 healthy peers, the maximum observed times across three repeats were:

| Failed child | Safe observation | Teardown observed | Explicit replacement ready |
| --- | ---: | ---: | ---: |
| Provider | 1.187 ms | 1.189 ms | 1.060 ms |
| Channel | 0.874 ms | 0.876 ms | 1.381 ms |
| Input worker | 1.065 ms | 1.067 ms | 1.186 ms |
| Provider supervisor | 0.336 ms | 0.338 ms | 1.587 ms |
| Initializer supervisor | 1.673 ms | 1.675 ms | 0.773 ms |
| Shared control | 1.162 ms | 1.163 ms | 1.065 ms |
| Admission worker | 1.167 ms | 1.169 ms | 1.233 ms |
| Shared session supervisor | 0.835 ms | 1.132 ms | 0.755 ms |

Safe observation is a semantic closed event for allocation failures and a **capability DOWN**
for shared failures. A dead shared controller cannot send a semantic notification; a future room
owner must translate its capability monitor. Teardown additionally observes provider, input and
allocation tree DOWN. These are different measurements. Replacement includes creating a new
capability for shared failures. Three observations per failure type are not a stable tail estimate.

Healthy turn-end p95 in the injected round ranged from 1.401 to 2.450 ms across failure types
(96 observations per type). Process count returned to 245 after every trial; memory ranged
85.0–89.3 MB. [The report](../labnotes/20260919-1927-speech-faults-concurrent.json) retains repeat-specific
percentile summaries, fault-round samples and overlap counts. The [earlier sequenced
trial](../labnotes/20260919-1927-speech-faults.json) is retained: it measured replacement after
teardown while healthy peers could be waiting, so it does not establish replacement under
continuing input load. This is bounded local cleanup evidence, not a
long-running leak or production capacity claim.

## Legacy latency comparison

The unchanged `bench/speech_latency.exs` passed **68,400 measured turns** with alternating
legacy/native repeats at 1, 8 and 32 owners, including a held native initializer. It retains
its original PCM fixture and latency definitions. At 32 owners, p95 was:

| Metric | Legacy | Native | Native with held peer |
| --- | ---: | ---: | ---: |
| First text | 2.133 ms | 2.578 ms | 2.229 ms |
| Turn end | 1.526 ms | 1.567 ms | 1.376 ms |

The preceding repair run recorded native first-text/end p95 of 2.677/1.615 ms. These independent
runs do not isolate a causal speedup from the new worker, and native still has overhead against
legacy in the current paired run. [Current report](../labnotes/20260919-1927-speech-latency.json).
There was no correctness failure. No hosted-service, codec, TTS playback, production capacity,
or machine concurrency ceiling is established by these isolated STT tests.

## Adoption churn follow-up

The unchanged `bench/speech_adoption.exs` passed **16,236 measured turns** in three paired
repeats of direct/adopted candidates at 1, 8 and 32 scopes. Burst and paced trials retain their
original workload: 20 ms waits after completed PCM pushes, plus processing, and healthy input
pauses during candidate churn. They are not continuous real-time call simulations.

At 32 scopes, adopted healthy-peer first-text/end p95 was 2.736/1.741 ms burst and
1.564/0.499 ms paced. Old-lease rejection p95 was 0.421/0.277 ms; candidate close through
teardown was 2.072/0.562 ms. No stale lease closed an adopted allocation; current consumers
closed successfully and exact PCM/event checks passed. Process count returned to 245 in all
36 trials; post-trial memory was 86.1–89.7 MB. [Report](../labnotes/20260919-1927-speech-adoption.json).
Paired direct controls and full percentile summaries remain in that report; favorable adopted
values do not establish that adoption improves performance.

GPT-6 Astra xhigh reviewed the final ownership/deadline code and concurrent diagnostic, finding
no remaining R blocker conditional on root acceptance and documentation. It distinguished
static race findings, their subsequent deterministic reproductions, and measured load evidence.
All five root gates passed on the reviewed source: **1,868 tests, zero failures, 40 excluded**
(seed 892574). Checkpoint R is accepted. A and D remain required before room migration.
