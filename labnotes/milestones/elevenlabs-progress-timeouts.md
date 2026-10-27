# ElevenLabs progress timeouts

Status: caller checkpoint implemented; response progress follows in the next
checkpoint. Both checkpoints are validated before their commits.

## Outcome and prerequisites

Allow long native caller turns and progressing assistant responses without an
adapter-imposed total duration cap. Preserve bounded waits for missing protocol
events and stalled delivery, using provider events and engine acknowledgements.
No local VAD is introduced.

Prerequisite: [ElevenLabs Realtime speech-to-speech](elevenlabs-realtime-models.md).
Contracts: [Realtime adapter](../../docs/elevenlabs-realtime-models.md),
[speech provider contract](../../docs/speech-provider-contract.md), and
[output admission](../../docs/sts-output-admission.md).

## Tasks and acceptance

- [x] A — Caller finalization
  - [x] Demonstrate that the existing deadline can close active speech.
  - [x] Start the final-transcript deadline only after native speech stop.
  - [x] Verify missing post-stop evidence still closes and settled timers are harmless.
  - [x] Run root gates and independent GPT-6 Astra xhigh review before committing.
- [ ] B — Response progress
  - [ ] Demonstrate failures for progressing generation and credited delivery.
  - [ ] Start explicit response-creation waits at dispatch, not queue insertion.
  - [ ] Track provider progress, delivery progress and cancellation separately.
  - [ ] Fence stale timer messages and keep unrelated events from extending waits.
  - [ ] Preserve native response-start, fixed-opening and tool-continuation contracts.
  - [ ] Verify long progress, genuine stalls, cancellation and queued responses.
  - [ ] Run all five root gates and Lean verification.
  - [ ] Resolve independent GPT-6 Astra xhigh findings and obtain clean final review.
  - [ ] Commit a coherent implementation checkpoint and synchronize evidence/index.

## Design review

Initial local review: caller finalization must depend on native stop, not speech
onset. Response creation, provider output, playback credit and cancellation are
different obligations. Queue residence and active caller speech do not establish
provider failure. Progress must refresh only its own obligation; cancelled or
completed obligations must invalidate already-delivered timer messages. Buffer,
identity, authorization and supervision bounds remain applicable independently.
Independent GPT-6 Astra xhigh review cleared checkpoint A. Its separate design
review requires preserving fail-closed handling of a second native stop while an
earlier origin still lacks a response identity. Resumed speech suspends the
native creation wait, but does not authorize guessing a different origin. Only
audible, non-interrupted completed responses await a final transcript; tool-only
responses must not acquire a transcript timeout. Keep the channel's existing
15-second per-credit bound.

## Verification evidence

Caller focused suite: 20 tests pass after the expected red regression. Independent
GPT-6 Astra xhigh source review is clean. The first full run had one Gateway
CallIngress failure, which passed its targeted rerun. Before persisting either
checkpoint, the final combined source passed all five root gates and Lean:
4,503 tests, zero failures, 159 exclusions, nine Lean build jobs and one passing
oracle replay. The next checkpoint records the response implementation and final
combined acceptance evidence.
