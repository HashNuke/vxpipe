# ElevenLabs progress timeouts

Status: complete. All acceptance checks and final independent GPT-6 Astra xhigh
review pass. The implementation is recorded in two coherent checkpoints.

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
- [x] B — Response progress
  - [x] Demonstrate failures for progressing generation and credited delivery.
  - [x] Start explicit response-creation waits at dispatch, not queue insertion.
  - [x] Track provider progress, delivery progress and cancellation separately.
  - [x] Fence stale timer messages and keep unrelated events from extending waits.
  - [x] Preserve native response-start, fixed-opening and tool-continuation contracts.
  - [x] Verify long progress, genuine stalls, cancellation and queued responses.
  - [x] Run all five root gates and Lean verification.
  - [x] Resolve independent GPT-6 Astra xhigh findings and obtain clean final review.
  - [x] Commit a coherent implementation checkpoint and synchronize evidence/index.

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

Caller focused suite: 20 tests pass after the expected red regression.

Response regression suite: 11 tests, initially seven failures from legacy fixed
deadlines or missing progress bookkeeping, then all green. Full focused
ElevenLabs directory: 145 tests, zero failures, four excluded integration cases.
Independent GPT-6 Astra xhigh source review of both checkpoints is clean.
The first full umbrella run completed
4,492 tests with one Gateway failure; the affected test passed its targeted rerun.
The local WebSocket integration test passes.

Final combined source passes formatting, warnings-as-errors compilation, strict
Credo, the full umbrella suite (4,503 tests, zero failures, 159 exclusions), the
unused dependency check and Lean (nine build jobs and one passing oracle replay).
Gateway passed all 863 tests in the final run; no Gateway changes were necessary.
No hosted requests or UI changes were required for this adapter-only correction.

Final independent review verified both checkpoint diffs, their documentation and
all gate evidence. It is clean, with no remaining actionable code, test or
contract findings. Both design findings are resolved and covered by regressions.
