# STS output admission

Decision: the speech consumer explicitly authorizes each STS output generation
after its policy checks. This is the shared contract for checkpoint A of
[Agent speech-to-speech](milestones/agent-speech-to-speech.md); room integration
and actual Morse responses remain checkpoint B.

## Ownership and lifecycle

`Session.admit_output(session, provider_turn_ref)` requires the current consumer,
an active STS allocation and acknowledged readiness. It returns an
`OutputTurn` containing the allocation, provider turn and a fresh engine output
reference. The provider receives a bounded, single-slot permission message:
`{:vxpipe_speech_output, channel, provider_turn_ref, output_ref}`.

The output reference admits raw mono linear16 PCM through `Channel.submit/3`
and the existing single-chunk credit protocol. Audio input and explicit text
input remain separate commands; neither implicitly opens an output slot.
The engine-issued reference fences an earlier generation even when a provider
reuses its turn reference. Provider identity and allocation ownership remain
checked by the scoped channel.

The provider emits `:output_completed` with both references after all audio
credit returns. That marks generation complete. The consumer acknowledges the
event, waits for sink settlement and calls `Session.settle_output/3` with the
output handle and actual played milliseconds. Playback cannot exceed the
credited PCM duration. Settlement releases the single output slot; generation
completion alone does not. Close, owner loss and provider loss revoke output
through the existing allocation lifetime. Expired queued admissions cannot
create late output permission.

The shared byte and credit ledger is reused without a TTS `speak` command,
input-character measurement or TTS usage emission. The TTS settlement operation
rejects STS allocations so it cannot bypass the STS completion acknowledgement
or playback bound. The new `STSOutput` module owns STS admission and settlement;
`Channel` continues to own delivery, caller validation and lifecycle.

## Alternatives and implications

- Opening output on every audio chunk would conflate microphone admission with
  response permission and could create many generations for one input turn.
- Opening output on `:input_submitted` would exclude audio-driven responses and
  couple conversation generation to complete-text TTS semantics.
- Letting arbitrary output audio open its own turn would move admission policy
  into the provider. It would also lose the fresh reference needed to reject
  late output from a previous generation.
- Deferring all credited output to room wiring left checkpoint A's independent
  provider unable to deliver output at all. A consumer-authorized contract
  allows that boundary to be tested before room policy and sinks are connected.

One outstanding output generation deliberately provides backpressure. The
consumer must not release it until its selected transcript and transport sink
have settled. Transcript source selection, interruption fencing, history
reconciliation, tool execution, STS usage and transport-qualified public turn
projection remain the later milestone's responsibilities. This contract does
not claim those workflows are complete.

## Selected transcript settlement

The 2026-09-22 repair enforces the already-declared transcript settlement mode.
Provider events carry bounded cumulative snapshots. An explicit final freezes
the snapshot for `:transcript_end`; acknowledged output generation completion
freezes the last preceding snapshot for `:generation_boundary`. The engine never
turns a partial snapshot into a final merely because playback drained. In
provider-transcript mode, both text and generation must settle before the matching
playback can complete publication.

An explicit final may arrive after generation or playback. One non-renewing
deadline begins at generation acknowledgement, defaults to five seconds and
accepts positive internal overrides no larger than thirty seconds. It is scoped
to the fresh engine output reference and cancelled on final/settlement/fencing.
Bounded sink finalization consumes the same budget; absolute expiry prevents a
queued final from being accepted after it expires.
Missing final text closes the uncertain allocation; generation-boundary profiles
with no snapshot fail at that boundary. No source switch or history replay occurs.
The separately selected output-STT path retains its recognizer-owned finalization.

Rejected alternatives: treating any snapshot as final publishes partial text;
waiting without a bound retains the output slot indefinitely; restarting the
budget on each update lets a provider postpone settlement indefinitely; allowing
post-final replacement contradicts the provider's settled evidence. A final
transcript still does not prove a remotely heard prefix or reconciled model
history. Those interruption guarantees remain open in the milestone.

Focused verification exercises the shared event/channel boundary, real Morse
finality, delayed playback/final ordering, immutable text, deadline validation,
timeout failure, different-turn rejection and fresh-output-reference timeout
isolation. Upstream reference retirement remains separately open. See
`labnotes/20260922-1751-sts-transcript-settlement.md` for red-green evidence.

## Verification

`STSConformanceTest` exercises audio- and text-driven admission, credited PCM,
completion/settlement separation, duplicate input evidence, transcript coverage,
JSON tool arguments and descriptor controller consistency through an independent
provider. The initial five tests failed for the five review findings before
implementation. `STSOutputTest` covers consumer authority, readiness, queued
timeouts, reference isolation, provider-loss containment and ten concurrent
allocations completing 100 output turns. Further red tests caught non-PCM
descriptor admission and the cross-kind settlement bypass before their fixes.

Detailed results and root checks are recorded in
[`finish-sts-contract` labnotes](../labnotes/20260922-0708-finish-sts-contract.md).
