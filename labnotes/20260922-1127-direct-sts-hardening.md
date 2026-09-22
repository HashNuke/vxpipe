# Direct STS hardening

## Scope and starting evidence

The user requested direct implementation instead of delegation. Preserve all
existing milestone work and unrelated runner changes; no commits authorized.
The latest Call Engine baseline passes 992 tests (14 excluded, seed 868958).
Root format, warnings-as-errors compile and unused-lock checks passed, but
strict Credo reports five oversized modules. A full root test run has not yet
completed successfully. No billable hosted calls are authorized.

## Pending-turn regression

Static inspection reproduced review finding 10: the controller appends pending
turns without a bound, and output-recognizer readiness clears the remaining
queue after admitting its first turn. The new tests delay recognizer readiness
using a provider acknowledgement (no sleeps), submit distinct typed turns, then
assert ordered public start/completion events. A second test submits 17 turns
against a 16-turn budget and requires explicit failure and supervised cleanup.

This is independent of conversation context restoration after a main STS
session restart. Existing output-STT recovery restores only the recognizer for
the next turn, not the conversational model's memory.

Both queue tests failed before the fix: the second queued reply never started,
and the overflow notification never arrived. The initial unpaced overflow probe
hit the existing channel-event limit instead; waiting for each input transcript
isolated the controller queue under test. After adding the queue limit, a second
failure exposed `Telemetry.provider_failure/3` rejecting `:sts`, which crashed
before notifying the room. Extending its closed capability list fixed that
failure path. The capability/output-STT/telemetry group passed 36 tests, seed 0.

## Responsibility extraction

With the behavior green, extracted the STS output lifecycle into
`Capability.SpeechToSpeech.Output` (31 capability tests still pass), room STS
tool authorization/execution into `SpeechToSpeech.Tools`, shared room event
identity into `SpeechToSpeech.Evidence`, room playback routing into `Playback`,
speech provider configuration into `PlanStartup.SpeechProviderResolution`, and
Google output credit/buffering into `Google.STSOutput`. These are module-only
extractions: no new process, mailbox or supervisor. An initial compile found a
missed configuration-error helper import and an unused room import; repaired
both before wider verification.

The affected plan, room, capability, Google fixture, Morse round-trip and
ten-session concurrency group passed 111 tests (seed 0). Strict Credo passed
after extraction. No independent review or real ten-room load is implied.

## Delayed onset double interruption

A deterministic real-Morse regression retains the provider onset owner message
until its reply has reached sink finish, then dispatches that onset through
the room handler. Before the fix it received an interruption for the **new
reply**, proving that the room's second unqualified interrupt could cancel the
generation created by the same onset. Removed that duplicate command; the
capability remains responsible for prompt fencing and the room publishes only
the resulting turn-qualified interruption evidence. The room/capability group
passed 37 tests with the earlier problematic seed 264975.

The existing capability barge-in test also issued a manual interrupt after a
complete second utterance. It now asserts provider-driven fencing directly,
using pinned final-input acknowledgements instead of the 100 ms mailbox-drain
wait. The first rerun found two remaining users of the removed helper; those
were changed to the same pinned evidence before the passing run.

## Context-restoration feasibility

Read the actual main-session loss and planned-renewal paths and checked the
official Google Live session-management and WebSocket API references. Native
resumption and conversation-history input exist, but full fresh-session
reconstruction is not implemented. The proposed boundary, rejected shortcuts,
and required evidence are recorded in `docs/sts-context-restoration.md`; this
does not broaden the milestone or authorize billable calls.

The full root run on this checkpoint completed 2,142 tests with two failures
(42 excluded, seed 0). Both failures are Gateway native WebRTC transfer fixtures
still configuring legacy Morse modules, the same provider-registry mismatch
previously repaired in Call Engine. Migrated those fixture keys to the public
Morse provider namespace; focused rerun is tracked separately. The root run
predates the subsequent Google resumption-handle implementation.

The two repaired native WebRTC transfer tests passed (seed 0; 187.5 seconds,
66 other file tests excluded). This confirms those two root failures were the
stale fixture-provider namespace, not a reason to extend test timeouts.

The final root run, including the subsequent Google handle-resumption work,
passed 2,151 tests with zero failures (42 excluded, seed 0). Format,
warnings-as-errors compile, strict Credo, unused-lock and whitespace checks
also passed. This is local verification, not completion of the milestone's
hosted, integrated-load, rendered-UI or independent-review acceptance gates.
