# Native TTS handoff regression

> Relocated from `docs/native-tts-deadline-findings.md` on 2026-10-09. First recorded source commit: `642779e0afe9` (2026-09-20T07:41:06+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260919-2159-repair-tts-handoff](20260919-2159-repair-tts-handoff.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [simpler-speech-integrations](milestones/simpler-speech-integrations.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Checkpoint D was paused under the user's tested-instability rule and resumed
after explicit approval of the proposed fix. Focused, load and all five umbrella
checks pass on the repair. R and A remain
accepted at commit `935d554`; D is uncommitted and unaccepted. Existing rooms
still use the legacy providers. These findings concern the isolated native TTS
implementation, not a demonstrated failure in production rooms or `main`.

## Reproduction evidence

From `apps/vxpipe_call_engine`:

```sh
mix test test/vxpipe/call_engine/speech/tts_deadline_test.exs --seed 530504
```

The initial run on 2026-09-19 used seed 530504 and finished with **2 tests,
2 failures** in 0.5 seconds. An expanded five-case suite subsequently reproduced
adoption and rejected-input cleanup failures before repair (same seed, five
failures). All five cases passed after the minimal Channel repair.

1. **Readiness escapes its startup deadline.** The test holds the provider's
   startup, intercepts the new Output authorization request, then suspends
   Channel. Output commits authorization within the original budget. The test
   resumes Channel only after the absolute startup deadline. Instead of the
   expected allocation-closed notification, the consumer receives a typed
   `:ready` event (sequence 1).
2. **Wrong-direction input fails a usable TTS session.** After acknowledging
   native TTS readiness, `Session.push_audio(allocation, <<0, 0>>)` returns
   `{:error, :session_failed}` instead of `{:error, :unsupported_operation}`.
   The test's subsequent assertion that synthesis remains usable is not reached.

The first test uses explicit barriers and a deadline timer, not a probabilistic
load-induced delay. It proves that the new handoff permits late readiness under
that scheduling interleaving. It does not measure the frequency of that
interleaving under ordinary load, establish a capacity limit, or attribute a
latency distribution to the change.

## Cause and review

Before the repair, the D change added a synchronous `Output.control(...,
{:authorize, consumer}, deadline)` call after Channel's existing deadline/allocation
checks. When that call returned, Channel dispatched readiness without checking the
original budget again. ScopeControl had already activated the allocation and
settled startup expiry, so its token did not reject this late delivery. The test
isolates the new wait between the check and dispatch. The same ordering appeared
in adoption, now covered by its own regression test.

The audio input handler also lacked the TTS/STT kind guard already present in
`speak`. It admitted the command and invoked an unsupported provider callback,
which was normalized to the observed session failure.

GPT-6 Astra xhigh identified both paths during source review. The rejected-input
cleanup finding was also subsequently reproduced: cleanup received a deadline
22 ms later than the original input deadline in the controlled run, and Channel
did not retire when it processed the cleanup reply after expiry. Adoption
released late readiness in a test that suspended the API caller to prevent its
independent timeout cleanup from masking Channel's decision.

## Authorized repair and acceptance gates

- Recheck the original deadline and allocation validity after Output authority
  handoff, before acknowledging adoption or releasing readiness. Retire the
  allocation if the handoff finishes late or its authority is uncertain.
- Reject wrong-direction operations before admitting an input ticket, preserving
  the active allocation for valid requests.
- Carry the original command deadline through rejected-input cleanup and check
  it before replying. Add a focused red test for this path before changing it.
- Keep the current regression tests, add adoption coverage, rerun R/A isolation
  and failure tests, and repeat the load diagnostics after the repair. Load
  evidence must include delivery/end latency and fault/cleanup behavior.
- Complete D's cancellation, playback accounting and standalone load/demo gates,
  obtain independent review, and rerun all five umbrella checks on the completed
  D implementation before accepting D.

Continuing with a known failing handoff or relaxing the deadline assertion is
rejected. A faster machine cannot guarantee a scheduling deadline. The finding
does not yet justify discarding the scoped architecture: the proposed correction
preserves its ownership model. The minimal repair is implemented and passes the
five focused regressions, the broader speech/Morse selection, serial load lanes
and all five umbrella checks. D's remaining functionality is still unaccepted.

The initial PCM streaming test and 101 speech/Morse tests passed before these
regressions were added. Those earlier passes do not accept D. Full umbrella
checks now pass on the repair; the remaining D cancellation/playback load
diagnostics are not covered by the narrower repair verification below.
See the [checkpoint labnote](20260919-2049-native-tts-streaming.md).

## Repair verification

GPT-6 Astra xhigh reviewed the repaired source, five regressions and the load
harness. No remaining runtime repair blocker was identified. The five regressions
passed with seed 530504; the broader speech/Morse selection passed **106 tests**
with seed 315087. Explicit monitors confirm provider, Output and allocation-tree
termination on the failed handoffs. Adding those monitors initially exposed a
test-only ordering assumption between `:DOWN` and the safe closed notification;
the test now requires both outcomes without imposing cross-process message order.

The [final TTS report](20260919-2159-tts-handoff.json) covers 36 trials:
1/8/32 scopes, direct/adopted startup, 0/2 ms simulated sink-acceptance delay,
three repeats and eight rounds per scope. It passed **3,936 synthesis requests,
3,936 STT turns and 492 injected Output failures with explicit replacement**.
Seven rounds per scope complete an STT turn while the first TTS envelope's exact
audio credit remains withheld. The fault round completes STT after killing Output
and then replaces TTS. Each successful synthesis matches independent PCM for `E`.

At 32 scopes, the following are the largest per-repeat p95/p99 values, in ms;
they are not percentiles pooled across repeats:

| Mode / simulated sink delay | First audio | Generation end | Last sink acceptance + credit ACK | STT turn end |
| --- | --- | --- | --- | --- |
| Direct / 0 ms | 1.030 / 1.611 | 17.096 / 17.681 | 16.213 / 16.829 | 0.872 / 1.687 |
| Adopted / 0 ms | 1.194 / 1.738 | 24.171 / 26.829 | 22.702 / 25.624 | 0.938 / 1.242 |
| Direct / 2 ms | 1.015 / 1.955 | 64.293 / 65.218 | 63.220 / 64.179 | 1.440 / 2.272 |
| Adopted / 2 ms | 1.176 / 1.949 | 65.426 / 67.713 | 64.239 / 66.586 | 0.917 / 1.422 |

Maximum observed fault notification/teardown/replacement-ready durations across
all trials were **2.546 / 2.547 / 5.550 ms**. Notification and teardown timings
are upper bounds observed after finishing sibling STT work. Full candidate setup
includes adoption/lease work, so it is not a like-for-like provider-ready metric.
Process count returned to **245** after every trial, memory was **84.8–87.3 MB**,
and explicit dynamic-child counts were empty. These are finite-run observations,
not proof against every possible leak.

The harness intentionally uses unpaced local synthesis, a short fixture, fixed
direct/adopted order and no warmup. Selective receives do not independently prove
every control/audio ordering boundary. Physical playback, cancellation, hosted
providers, room integration and capacity remain outside this repair-load claim.
D's additional acceptance tests and controlled playback measurements remain open.

The existing [STT latency lane](20260919-2159-stt-latency.json) passed
68,400 measured turns. At 32 allocations, p95/p99 first text was 1.435/2.234 ms
legacy, 1.880/3.077 ms native and 2.103/3.170 ms native with a held startup.
Turn end was 1.146/1.557, 1.253/1.809 and 1.349/1.942 ms respectively.
The [STT fault lane](20260919-2159-stt-faults.json) passed 72 trials
and 39,360 healthy turns; maximum safe notification/teardown/replacement-ready
was 3.916/16.991/6.745 ms. The longer teardown observation is retained; bounded
safe failure and exact descendant cleanup passed. These separate workloads do
not establish a TTS before/after speedup or a production concurrency ceiling.

The [adoption lane](20260919-2159-stt-adoption.json) also passed:
36 trials and 16,236 measured turns across burst/paced, direct/adopted operation
at 1/8/32 scopes. Exact ownership, stale-lease rejection and descendant cleanup
checks passed. Across the four distinct final diagnostic workloads, 131,868
successful measured turns passed, plus the 492 deliberately failed TTS requests.

All five root checks passed: formatting, compilation with warnings as errors,
strict Credo, `mix test`, and unused dependency-lock verification. The full
umbrella run passed **1,886 tests, zero failures, 40 excluded**, seed **801819**:
MCP 37, Agent Runtime 95, Call Engine 788, Calls 117, Gateway 460, Artifacts 20,
Persistence 184 and Console 185. No runtime source changed during those checks.
Relative documentation links, JSON evidence and `git diff --check` also passed.
This closes verification of the authorized repair; D's cancellation/playback
work remains and no D checkpoint commit has been made.
The [repair labnote](20260919-2159-repair-tts-handoff.md) records progress.
