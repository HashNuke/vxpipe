# Scoped speech prototype and room experiment

Status: pre-approval experiment, 2026-09-19. Production migration remains paused.
This records executable evidence for the [ownership proposal](speech-session-ownership.md),
separately from acceptance of the [implementation milestone](milestones/simpler-speech-integrations.md).

## Question and experiment boundary

Can local speech execution preserve the existing room's policy, input, output, turn and
interruption behavior, including while another provider or output sink is held?

The test-only prototype has an explicitly supplied local supervisor, a temporary subtree per
allocation, responsive control, persistent Morse decoder/encoder workers, startup deadlines,
one outstanding TTS output credit and generation-specific cancellation. Provider initialization
runs after lightweight OTP startup. No prototype provider start goes through the rejected
global speech-session supervisor. Existing RoomRegistry is used for identity lookup only.

Trusted test transport settings connect these semantic workers to the **real existing room
capabilities** through a private compatibility bridge. CallSpec compilation, room policy,
ingress, model fixture, turn handling, interruption and output accounting execute normally.
The same room workload also runs through the existing Morse transports as the baseline.

Scopes are precreated under the test supervisor. This intentionally does not implement final
room capability nesting, purpose-specific production lookup/stop migration, queued admission
tokens, credential handling or removal of the existing global output/connector task supervisors.
Those production tasks remain in both compared room paths. Thus successful behavior here is
feasibility evidence for semantic provider substitution, not acceptance of checkpoint R/B/E.

## Behavioral proof

The focused tests exercise these boundaries:

- A held initializer and a healthy sibling share a local scope. The healthy session reaches
  readiness and recognizes independent PCM before the held initializer is released.
- Expired admission creates no allocation. Held startup expires. A ready message processed
  after the absolute startup deadline is rejected; TTS cannot submit before readiness.
- Owner loss terminates the allocation supervisor, control and held worker, verified with
  individual process monitors. Real-room shutdown also verifies descendant termination before
  explicitly stopping the outer test scope.
- Real room input produces one start, final transcript and turn end, followed by model text,
  exact independent output PCM and one confirmed agent completion on both paths.
- Joining a restricting participant through the real command path removes both transcript
  routing and saving. The STT allocation closes; later PCM produces no transcript/turn and
  no new provider is allocated.
- A prepared STT replacement can be discarded without replacing the active session. A later
  prepared generation is adopted through the real join/readiness path; old provider messages
  are ignored and fresh input still produces a complete correct response.
- With an output write held, independent PCM onset interrupts the sink before the new end gap
  is supplied. The replacement has exactly one completion and exact PCM under its own turn
  identity. Old request audio/credit cannot contaminate another generation.
- A failed output credit terminates the prototype allocation. One outstanding credit bounds
  generation. Direct credit expiry is bounded, although full final API conformance is pending.

The connection fixture gained an optional truthful input track: PCM16 kHz for this experiment,
with its existing Opus48 kHz default retained. The sink fixture gained a controlled unblock
operation that is allowed only when no write is pending. Both changes had focused failing
tests before implementation.

Review found two prototype contract defects and an evidence weakness before final measurement:
TTS accepted input before readiness, failed output credit left a silent request, and the
recorder combined interrupted/replacement PCM. Focused failing assertions reproduced these;
the test-only prototype/recorder were corrected. This is not evidence of a defect in the
unchanged production room path. The migration remained paused throughout.

## Measurement method

`bench/scoped_speech.exs` runs three repeats in alternating baseline/prototype order, with
1/8/32 simultaneous real rooms. Each burst trial has three warmup and twenty measured turns
per room. Another 32-room lane holds an initializer in the first call's local scope while all
calls continue. A separate 20 ms-paced input lane uses 1/8 rooms and two measured turns after
three warmups. The small paced sample is a timing/behavior check, not a capacity estimate.

Input is independently constructed E: raw mono 16 kHz linear16, a 60ms700 Hz dot and 840 ms silence.
Output is compared byte-for-byte with an independent E fixture using a 20 ms dot and 280 ms gap.
Fixture construction is outside the timed interval. Paced frames follow absolute 20 ms due
times; per-turn maximum admission latency and input lateness are recorded separately.

A dedicated recorder timestamps messages on arrival, retaining room/incarnation/connection
and turn identity. Every measured turn asserts exact transcript, exact output PCM, attribution
and start/final/end/text/completion counts. Metrics use monotonic microseconds:

| Metric | Boundary |
| --- | --- |
| Input admission | Maximum ingress push-call duration among a turn's chunks; not provider submission. |
| Speech start / first text | Start of input delivery to the observer receiving the room event. |
| Turn end | Immediately before the final chunk to the room turn-end event; paced gap time is excluded here. |
| First audio | Immediately before delegated Speak transport submission to observed first sink invocation. A blocked sink notification is not acceptance. |
| Sink finish | The same Speak submission to observed sink finish invocation, after generation and accepted output; not a raw provider terminal timestamp. |
| Playback acknowledgement | Controlled sink completion acknowledgement to observed AgentTurnCompleted. |
| Total | Input start to observed AgentTurnCompleted. Paced input includes the 900 ms signal duration. |

The sink acknowledges playback immediately when finish is invoked. These are processing and
control measurements, **not acoustic playback, WebRTC/network latency or hosted-service timing**.
TTS output is generated as quickly as bounded sink credit permits; it is not paced playback.

Both paths use the same test-only timestamp wrapper at the TTS transport boundary. An initial
observer-only measurement subtracted receipt of the room's TextOutput event from sink receipt.
Those notifications have different senders and no arrival-order guarantee; 48 negative TTS
deltas exposed the invalid anchor. The corrected source timestamp precedes synthesis, and every
reported duration is now checked nonnegative. The initial run's valid STT measurements are
retained separately, including its slower paced turn-end result.
These durations include recorder scheduling. Replacement-turn latency is not reported: the
simple marker retains the first Speak in that recorder interval. The stress lane reports
independently anchored interruption measurements and ordinary healthy-call timings only.

`bench/scoped_speech_stress.exs` starts 8/32 healthy paced calls plus separate blocked-output and
policy-revocation calls. It verifies the healthy calls have started but remain unfinished both
before and after the control actions. It measures PCM onset to sink interruption/room
interruption event and the whole policy-revocation operation (including checked teardown and
denied-input probe). Each healthy call and the interrupted call's replacement must then finish
with exact output. There are three alternating repeats per path/concurrency.

## Results and verification

The corrected main run passed **8,868 measured turns**, plus warmups. Two fresh-VM follow-ups
passed **288 paced turns** and **3,840 burst turns**. Every measured turn met the exact content,
identity and event-count assertions. These are three alternating repeats per workload/path on
Elixir 1.19.5, OTP 28, eight online schedulers; they are not independent production samples or
an established capacity limit.

Main-run pooled p95/p99, milliseconds:

| Workload / metric | Existing transport | Scoped prototype |
| --- | ---: | ---: |
| 32 burst calls: first text | 2.301 / 3.819 | 5.096 / 16.698 |
| 32 burst calls: turn end | 3.612 / 4.895 | 7.603 / 23.300 |
| 32 burst calls: first audio | 1.148 / 2.122 | 2.658 / 7.368 |
| 32 burst calls: sink finish | 10.507 / 20.957 | 17.883 / 213.800 |
| 32 calls with held startup: turn end | 4.907 / 7.204 | 4.487 / 6.339 |
| 8 paced calls: turn end | 7.396 / 8.388 | 0.981 / 4.267 |

**Latency parity is not established.** The initial run's 8-paced-call turn-end p95 was
2.801 ms existing versus 15.307 ms scoped (48 turns/path). The corrected main run did not repeat
that ordering. A larger paced follow-up (144 turns/path) measured 2.773/5.200 ms existing versus
2.418/3.875 ms scoped at p95/p99. Thus the original paced observation remains evidence of
variability, not a repeatable demonstration that this design delays paced turn ends.

The corrected main run also had a large scoped burst output tail concentrated in repeat 2:
sink-finish p99 reached 222.757 ms in that trial. The burst follow-up (1,920 turns/path) measured
sink-finish p95/p99 of 14.619/28.680 ms existing versus 13.460/16.282 ms scoped. However, its turn-end
p95/p99 remained higher for scoped execution: **4.513/7.867 ms versus5.708/9.529 ms**. Scoped
turn-end p95 was higher in each of those three paired repeats. This is a measured overhead
in this harness; its source and production significance have not been isolated. Neither the
large outlier nor the smaller consistent difference is hidden by the passing correctness gates.

Process counts returned to their trial-start values after measured turns in every main trial.
This excludes net process accumulation in those short trials, not memory/history growth or
all possible leaks. The separate descendant-monitor assertions verify allocation teardown.

Raw evidence: [main run](../labnotes/20260919-1711-scoped-speech-metrics.json),
[paced follow-up](../labnotes/20260919-1711-scoped-speech-paced-check.json),
[burst follow-up](../labnotes/20260919-1711-scoped-speech-burst-check.json), and
[first-pass summaries](../labnotes/20260919-1711-scoped-speech-first-pass.json).
The first-pass TTS fields are explicitly invalidated; its STT fields remain relevant.

All 12 control-under-load trials passed: 240 healthy paced turns completed alongside 12
permission revocations and 12 interrupted outputs with exact replacement responses. For
32 healthy calls plus the two control calls, the three-repeat ranges were:

| Control measurement, ms | Existing transport | Scoped prototype |
| --- | ---: | ---: |
| PCM onset to sink interruption | 0.081–0.091 | 0.082–0.096 |
| PCM onset to room interruption event | 0.118–0.134 | 0.127–0.149 |
| Policy revoke, teardown and denied-input probe | 0.407–0.513 | 0.456–0.507 |

These are three observations per group, not percentile estimates. The permission test removes
transcript routing and saving; it does not exercise audio-recipient permissions or persisted
recording deletion. See [stress samples](../labnotes/20260919-1711-scoped-speech-stress.json).

All 11 focused experiment tests pass. Root format, warnings-as-errors compilation, strict Credo
and unused-lock checks pass. The full root test gate is **not green**: it retains the known
global startup-isolation regression and also reported a prepared WebRTC decoder test failure.
On a focused `mix test --failed` rerun, the decoder test passed and the original startup failure
remained. No causal link from the experiment to the decoder failure was established. This
does not justify a production rollback or claiming that the entire suite passed.
Further evidence and review are in the
[experiment labnote](../labnotes/20260919-1711-scoped-speech-experiment.md).

## Decision and next checkpoints

Keep production migration paused. This experiment supports local semantic execution as a
candidate: real room behavior survives the tested substitution and the held initializer does
not block sibling recognition. It does not establish full permission coverage, production
stability or latency equivalence. The latency observations do not yet prove that production
calls become unstable because of this change; no production path was migrated.

Before approval of implementation, agree a latency budget and preserve this paired workload as
a gate. Checkpoint R still owns actual room-local parentage, bounded queued admission, exact
lease/generation teardown and shared-capability failure. Checkpoints B/E must add audio-route
revocation, recording/privacy boundaries, output-recipient permissions and separate opening /
private-transfer consumers to the new path. Instrument submission, worker completion and room
publication separately if investigating the measured burst overhead; observer timing alone
cannot assign its cause. No implementation milestone checkbox is completed by this experiment.

## Reproduction

From `apps/vxpipe_call_engine`:

```shell
mix test test/vxpipe/call_engine/speech/scoped_experiment_test.exs test/vxpipe/call_engine/speech/scoped_room_experiment_test.exs --seed 42
MIX_ENV=test mix run bench/scoped_speech.exs /tmp/scoped-speech.json
MIX_ENV=test mix run bench/scoped_speech.exs /tmp/scoped-speech-paced-check.json paced-check
MIX_ENV=test mix run bench/scoped_speech.exs /tmp/scoped-speech-burst-check.json burst-check
MIX_ENV=test mix run bench/scoped_speech_stress.exs /tmp/scoped-speech-stress.json
```

Run benchmarks serially without another test/build load. Reports contain per-trial summaries
and samples; repeat counts and scope limits matter more than any single favorable percentile.

Hosted STT/TTS, credential/privacy redaction, genuine acoustic speech detection, usage-provider
submission semantics, audio-route/recording privacy, independent openings, private transfers
and final capability-tree migration require their existing milestone acceptance lanes. The
experiment does not infer their success from Morse or from unchanged legacy regression tests.
