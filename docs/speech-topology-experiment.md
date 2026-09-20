# Speech topology proof

Status: isolated preimplementation proof, 2026-09-20. Production speech code was not
changed by this experiment. Checkpoint D remains unaccepted and the existing
pending-Input cancellation reproduction remains red in the runtime worktree.

## Decision being tested

The proposed D repair removes the separate TTS Output state process and keeps the
request, event, PCM-credit, playback and cancellation state in the allocation's
Channel. Input remains a separate process because provider calls can block. The
provider remains separately supervised. STT and the usage consumer remain outside
the disposable TTS allocation tree.

The comparison holds the workflow constant and changes one process boundary:

~~~mermaid
flowchart LR
  C[Authorized consumer]
  U[Usage consumer]

  subgraph Split reference
    SC[Channel]
    SO[Output]
    SI[Input]
    SP[Provider]
    SC --> SI --> SP --> SO --> SC
  end

  subgraph Merged candidate
    MC[Channel with output state]
    MI[Input]
    MP[Provider]
    MC --> MI --> MP --> MC
  end

  C --> SC
  C --> MC
  SC --> U
  MC --> U
~~~

The split reference follows the current native credit direction: the consumer
acknowledges PCM directly to Output. The merged candidate acknowledges PCM to
Channel. Provider submission is one direct call in both variants. This corrects an
earlier prototype that routed the split acknowledgement through Channel and unfairly
added a hop to the reference path.

## Implemented contract

The test-only adapters use the production Morse Encoder and Decoder inside a
temporary one-for-all allocation supervisor. They model the selected native-style
workflow; they are not the actual native Session/provider modules. The split tree
has significant Channel, Output, Input and provider children;
the merged tree has Channel, Input and provider. Both implement the same observable
workflow:

1. An exact authorized consumer configures the allocation, receives one ready event
   and acknowledges it.
2. Speaking E returns an admitted request without waiting for Input callback
   completion. Input calls the incremental Morse encoder adapter with the API-entry
   deadline; the test barrier then holds Input after provider acceptance.
3. The provider publishes input-submitted with its bounded request ID. Channel
   commits the bounded input fact before acknowledging provider acceptance. Audio
   cannot reach the consumer until the submitted event is acknowledged.
4. The provider emits one 20 ms linear16 PCM chunk per exact credit. A watchdog owns
   every outstanding credit.
5. Input deliberately holds its accepted result while independent PCM is decoded by
   the real Morse decoder into speech-start, text and turn-end events.
6. The consumer fences the exact request. Cancel retains the original fence
   deadline while Input is busy, then dispatches through the same Input process.
   Exactly one cancelled terminal is acknowledged before replacement admission.
7. Speaking T validates and drains all incremental chunks with one credit
   outstanding, byte-for-byte equal to the Morse encoder result, then acknowledges
   one completed terminal. Played time is bounded by accepted/uncredited PCM.
8. Killing Channel or firing a credit/cancellation watchdog removes the disposable
   TTS tree. Independent STT remains usable and a committed input fact remains in its
   independently owned consumer.

The focused test first failed because the old constant-PCM/echo prototype had no
ready/event-ack contract. A later watchdog test failed because an abandoned fence
without an active cancel caller ignored expiry. The implementation then passed four
focused cases for both topologies.

## Load method and fixed gates

The topology comparison benchmark starts prepared allocations simultaneously at
1, 8, 32, 64, 128 and 256 concurrent call-equivalent scopes. It alternates
split/merged order across three repeats and runs eight complete workflows per scope.
Every cycle checks authority, event order and acknowledgement, request/provider/audio
correlation, the first E chunk and complete T output against exact PCM, decoded STT
semantics, queued cancellation without retry, usage fact retention and absence of
unexpected terminals/audio after synchronization. Each trial checks complete
supervisor cleanup.

Aggregate p99 is checked against fixed budgets at every tested concurrency:

| Metric | Budget |
| --- | ---: |
| First TTS audio | 10 ms |
| STT first text | 10 ms |
| STT turn end | 10 ms |
| Cancel return | 10 ms |
| Replacement first audio | 10 ms |
| Replacement completion | 100 ms |
| Complete workflow | 150 ms |

The comparison passes only when both conditions hold:

- whenever split passes every fixed budget at a concurrency, merged also passes
  every budget at that concurrency; and
- merged's first observed miss is no earlier than split's first observed miss.

The first miss is a diagnostic, not a capacity knee, because results can be
nonmonotonic. A 1 ms relative diagnostic at 32 scopes is reported but is not a
reliability gate.

Measurements ran serially in fresh BEAM VMs on an Apple M2 with 16 GiB RAM, eight
logical CPUs/schedulers, Elixir 1.19.5 and OTP 28. They cover local processing and
mailbox latency. They do not measure acoustic playback, room policy, codecs, network
transport or hosted providers.

## Results

Three decision runs on the final source passed both gates and completed **70,416
workflows** without a protocol/content assertion failure.

GPT-6 Astra xhigh independently recalculated all three reports, confirmed the
pointwise predicate and topology parity, and found no blocker to this isolated D0
feasibility gate. The review does not accept checkpoint D or clear the production
cancellation regression. It also records that watchdog tests inject expiry
messages; production migration must preserve real elapsed-deadline boundary tests.

| Fresh VM run | Split first miss | Merged first miss |
| --- | ---: | ---: |
| 4 | 64 scopes | 128 scopes |
| 5 | 32 scopes | 128 scopes |
| 6 | 128 scopes | 128 scopes |

Every decision run has an empty pointwise-violation list. First-miss locations still
vary substantially, so they are workload observations rather than capacity limits.

At 32 scopes, merged passes every fixed gate in all three decision runs. Split
passes in runs 4 and 6; its first-audio p99 is 20.301 ms in run 5. Across the runs:

| Aggregate p99 | Split range | Merged range |
| --- | ---: | ---: |
| First audio | 4.777-20.301 ms | 2.875-6.827 ms |
| STT turn end | 1.131-6.525 ms | 0.940-2.506 ms |
| Cancel return | 3.048-6.442 ms | 1.722-5.230 ms |
| Replacement completion | 22.959-37.727 ms | 15.402-31.699 ms |
| Complete workflow | 31.076-66.576 ms | 19.697-40.783 ms |

At 256 scopes, sampled peak process count is 2,744-2,764 for split and
2,416-2,508 for merged. Process memory is lower for merged in two runs and
6.327 MB higher in one, so this experiment establishes the process reduction but
does not claim a deterministic memory reduction.

Raw evidence:
[run 4](../labnotes/20260920-0632-tts-topology-native-4.json),
[run 5](../labnotes/20260920-0632-tts-topology-native-5.json), and
[run 6](../labnotes/20260920-0632-tts-topology-native-6.json).

Earlier prepared and native 1-3 reports are retained as development evidence only.
The prepared reports used constant PCM, echo STT and an extra split acknowledgement
hop. Native run 1 exposed the weakness in the original first-miss-only assertion:
split passed every gate at 64 scopes while merged replacement-first-audio p99 was
19.482 ms. That is a pointwise failure. The benchmark was strengthened, audio
validation/playback bounds and bounded provider IDs were added, and native runs
4-6 are the decision evidence. The counterexample is not discarded or described
as a passing production result.

## Implication and remaining proof

The result supports this bounded statement: **in three fresh runs of the final
isolated Morse workload, merged passed every fixed-budget concurrency where split
passed, and its first observed miss was no earlier**. It also removes one state
process per allocation while preserving the selected cancellation, validation,
playback-bound, watchdog and OTP teardown workflow.

This is enough to retain the simpler topology as the D repair candidate. It is not
evidence that current production code is already fixed. The next vertical slice
must move the actual Channel/Output state under red tests, rerun the original
pending-Input failure, then run the same fixed-gate load comparison against the
real implementation. Room, policy, permissions, barge-in, turn detection and
hosted-provider checks remain later D/E acceptance gates; no milestone checkbox is
completed by this experiment.

Generation adoption, full allocation lifetime authority and a complete historical
usage ledger are intentionally absent from these test adapters. Those contracts are
owned by the accepted R boundary or later D/E work and must be rechecked on the real
runtime implementation.

Static root checks and the four focused topology tests pass. The full umbrella test
gate is not green on the current production worktree: Call Engine completed 807
tests with the known cancellation failure and one startup-deadline lifecycle
failure under suite load. The lifecycle case and its complete 23-test file pass in
immediate same-seed isolation, so this experiment does not establish its cause.
Production migration remains paused until its own red tests and full gates pass.
