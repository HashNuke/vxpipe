# Scoped speech adoption repair

The 2026-09-19 isolated R implementation allowed an obsolete preparation lease to
close an adopted speech allocation. The regression test observed tree termination
and rejected input from the new consumer. The user authorized this repair and
required load verification before continuing. Existing production room speech
consumers have not migrated to this API.

## Decision and implications

ScopeControl now owns the current lifecycle authority for each exact allocation.
Channel synchronously commits adoption before enabling speech delivery. The
controller validates the stored handle, actual channel, current lease, lifetime
owner, new consumer and original deadline. Adoption removes the lease monitor,
installs the consumer monitor and settles the startup deadline. Close and failure
notifications use the current record. The supervisor parent remains unchanged.

A copied handle is identity, not a new grant of authority. The lifetime owner can
still close the allocation; a preparation lease can cancel while pending and
loses that authority after adoption. Cancellation committed first prevents
adoption; adoption committed first rejects subsequent old-lease cancellation.

Updating only Channel was the demonstrated bug. Removing all lease cancellation
would break pending preparation. Asynchronous authority transfer would allow
adoption to report success before close authority changed. The selected fix adds
one bounded lifecycle exchange, with no per-audio scope-control call and no
synchronous controller-to-channel callback.

## Focused evidence

Before the repair, the expanded lifecycle group had 12 tests and four failures:
stale lease close, wrong failure recipient, missing consumer-lifetime cleanup,
and altered ownership fields granting close authority. Those 12 tests passed
after the correction. Native STT and startup-isolation tests were adapted to the
explicit scope API while retaining their PCM/event assertions. The combined
speech group passed 45 tests; two additional expiry/lifetime cases also passed
within the 747-test Call Engine suite, bringing speech coverage to 47 tests.

The original held-initializer regression now requires all eight healthy sessions
to reach ready and decode exact `E` before the held provider is released. Ready
latency was 0–1 ms in the focused run, within the original 100 ms budget. A sibling
allocation in the same scope also reached ready and decoded while startup stayed
held. Returning `:starting` alone does not satisfy these assertions.

GPT-6 Astra xhigh reviewed the bounded authority correction and found no blocker.
That bounded repair did not accept R: private-init, deadline, ancestry and failure-boundary
implementation/verification remained open. The later [R completion report](speech-deadlines-and-failure-containment.md)
records their implementation and acceptance.
At that repair checkpoint, `Session.close/1` mapped a control-call timeout to success,
and input-failure cleanup started a fresh timeout budget. The later
[deadline repair](speech-deadlines-and-failure-containment.md) addresses those stalled-control paths; these load trials do not establish them. All five root gates passed; the umbrella run completed 1,845 tests with zero
failures and 40 excluded (seed 877669). Details are recorded in the
[repair labnote](../labnotes/20260919-1858-adoption-authority-fix.md).

## Adoption load experiment

Machine: Apple M2, 8 cores, 16 GiB RAM, 8 online BEAM schedulers. The raw report
also records Elixir/OTP versions. Run from `apps/vxpipe_call_engine`:

```shell
MIX_ENV=test mix run bench/speech_adoption.exs /tmp/speech-adoption.json
```

The test used 1, 8 and 32 local scopes, each with a healthy active STT allocation
and a repeatedly created candidate. Direct and adopted candidates ran in three
alternating paired repeats. Adopted candidates rejected the old lease's close,
survived that lease's death, decoded exact independent Morse PCM, and closed
through the current consumer. Healthy sibling turns span candidate churn.

Burst trials use 30 measured rounds per worker; paced trials use three. Each
trial has one excluded warmup round. Paced input uses 640-byte PCM chunks at
20 ms waits after each completed push (plus processing time), with a deliberate pause in active input while the candidate
runs. Processing latency starts at the relevant final chunk submission, excluding
the known Morse gap and earlier pacing waits. This is an isolated STT workload,
not a full real-time call simulation.

All **16,236 measured turns** passed exact event ordering, text, generation,
turn identity and terminal checks. Provider/tree termination was monitored;
allocation and lease supervisors were empty at each trial end. Post-trial process
count was 245 in all 36 trials; total memory ranged from 85.3 to 90.7 MB. This is
bounded cleanup evidence, not proof against every possible long-running leak.

At 32 scopes, p95 values in milliseconds were:

| Metric | Burst direct | Burst adopted | Paced direct | Paced adopted |
| --- | ---: | ---: | ---: | ---: |
| Candidate ready, including adoption when applicable | 5.763 | 3.814 | 5.379 | 3.128 |
| Healthy sibling first-text processing | 4.952 | 3.183 | 3.475 | 1.396 |
| Healthy sibling turn-end processing | 3.280 | 1.917 | 0.891 | 0.739 |
| Candidate turn-end processing | 3.473 | 2.009 | 0.863 | 0.961 |
| Candidate close through descendant termination | 3.265 | 1.475 | 0.845 | 0.767 |

Old-lease rejection p95 was 0.428 ms burst and 0.251 ms paced. Adopted healthy-sibling
turn-end p99 was 3.122 ms burst and 0.999 ms paced. The direct control had larger
outliers in several metrics; this is not evidence that adoption itself improves
performance. The paced candidate-end p95 was slightly higher with adoption.
No correctness failure or operation-deadline violation occurred in these trials.

Percentile summaries and repeat-specific results:
[adoption load JSON](../labnotes/20260919-1858-adoption-load.json).

## Legacy comparison and remaining overhead

The existing `bench/speech_latency.exs` retains its legacy path, independent PCM,
1/8/32 owners, alternating repeats and metric definitions. Its semantic side now
receives explicit scopes and waits for asynchronous readiness. A held initializer
uses a long deadline so it stays held throughout active-recognition measurements.
Two complete runs each passed **68,400 measured turns**.

In the second run, 32-owner p95 values were:

| Metric | Legacy | Scoped native | Scoped native with held peer |
| --- | ---: | ---: | ---: |
| First transcript | 2.013 ms | 2.677 ms | 2.574 ms |
| Turn-end processing | 1.511 ms | 1.615 ms | 1.573 ms |

The first run had a held-peer repeat with first-transcript p95 9.684 ms and
turn-end p95 4.864 ms; the other two held repeats were much lower. The complete
follow-up did not reproduce that outlier. Both reports are retained:
[first run](../labnotes/20260919-1858-speech-latency-fixed.json) and
[follow-up](../labnotes/20260919-1858-speech-latency-repeat.json).

The scoped native path still has measurable overhead against legacy at 32 owners;
this repair does not establish an overall speedup. These checks establish bounded
local behavior for the tested workload. They do not establish hosted-service,
network, codec, TTS playback, real-call capacity or a machine concurrency ceiling.
