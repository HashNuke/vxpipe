# Provider turn detection and contextual barge-in

Status: planned, 2026-11-14. Research and implementation tasks remain open.
The user requested this milestone before implementation.

## Runnable outcome

A conversational call responds without an extra Vxpipe settling timer after its
selected provider confirms the caller's turn has ended. Calls that rely on a
local activity detector such as Silero retain an explicit fallback endpoint
policy. While the agent speaks, ordinary acknowledgments let its audio continue;
an intentional interruption stops it promptly and gives the caller the floor.

The response target is at most **1,000 ms from the caller finishing a turn to
the first audible agent response**. Removing a timer alone does not establish
that result; detection, model generation, synthesis and delivery all count.

## Prerequisites and sources

- Completed [speech sessions](simpler-speech-integrations.md),
  [provider packages](provider-integration-packages.md),
  [persistent sessions](persistent-speech-sessions.md), and
  [transcript start and optional VAD](transcript-start-and-optional-vad.md).
- Existing [ElevenLabs native STS](elevenlabs-realtime-models.md) provides another
  controller profile to preserve and evaluate. Its earlier acceptance does not
  prove the multilingual interruption behavior requested here.
- Current [speech runtime](../../docs/en/development/speech-runtime.md),
  [call runtime](../../docs/en/development/call-runtime.md), and
  [provider integration guide](../../docs/en/development/providers-and-integrations.md).
- Reuse the boundary definitions in [debug console metrics](debug-console-metrics.md).
  Its unfinished UI work is not a prerequisite for runtime measurements here.
- Research starting point: ElevenLabs' [transcripts and commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies).
  Verify the selected model's actual protocol before implementing an adapter.

This milestone changes the earlier first-nonempty-transcript interruption
contract. Preserve that milestone as historical evidence; update current runtime
documentation and compatibility expectations when the new behavior ships.

## Required contracts

- One selected authority decides conversational turn completion. A provider's
  confirmed end-of-turn triggers response processing with **zero additional
  Vxpipe wait**. This removes deliberate settling delay, not required transcript
  assembly, authorization, correlation or ordinary processing time.
- A committed/final transcript segment is not automatically an end-of-turn.
  Distinguish genuine endpoints from partial revisions, forced long-input
  segments, eager predictions and resumed speech. Preserve truthful evidence.
- Retain bounded, cancellable endpoint waiting when the selected mode depends
  on local acoustic activity, including Silero. Renewed speech cancels a pending
  endpoint. Silero detects speech activity, not whether a thought is complete.
  Optional Silero onset alongside provider turn detection must not add a second
  endpoint timer. Unsupported modes must not silently claim semantic detection.
- Speech onset, interruption intent and turn completion are separate decisions.
  An acknowledgment must not cancel generation, clear queued audio, pause audible
  playback or schedule a competing answer. A real interruption can stop output
  before the caller finishes; answering waits for the caller's completed turn.
- Interpret acknowledgments in conversational context and across languages.
  Do not implement a universal ignored-word list: the same word can be an
  acknowledgment, a complete answer, or the beginning of a correction.
- Retain permitted caller transcript/history evidence without turning every
  acknowledgment into a new model request. A candidate that develops into an
  interruption retains its earlier words and produces one coherent caller turn.
- Respect existing room/provider interruption ownership, protected openings,
  playback settlement, cancellation, source epochs and permission boundaries.
  A provider that cancels audio automatically on any speech needs an explicit
  supported control mode; local filtering cannot undo that upstream cancellation.
- Pin selected policy with the call's existing configuration contracts and use
  DB-configured services. Do not restore application-level speech enablement.
  Define compatibility for old published revisions and already-running calls.

## Checkpoint A — Research and settle contracts

- [ ] Inventory current STT and STS adapters: speech onset, transcript final,
  semantic/gap endpoint, forced segment, resume and interruption ownership.
  Confirm which signals each supported model actually emits with primary docs
  and bounded protocol experiments; do not equate a model name with a capability.
- [ ] Define provider endpoint handling and the separate Silero/local fallback,
  including timer ownership, repeated speech, missing evidence and failure rules.
- [ ] Research multilingual acknowledgment versus interruption detection using
  context, transcript revisions and available acoustic/provider evidence. Compare
  accuracy, decision latency, language coverage and deployment requirements.
- [ ] Define behavior for uncertain intent, repeated acknowledgments, a short
  acknowledgment growing into a correction, and a pending/incomplete thought.
  Confirm Kannada wording, pronunciation and transliteration with native speech
  examples; preserve the user's supplied "oudhu" example in the test inventory.
- [ ] Record the selected design, rejected alternatives, compatibility changes,
  first supported provider profile and the measurable acceptance corpus. Research
  can proceed checkpoint by checkpoint; unresolved provider claims remain open.

## Checkpoint B — Turn completion without duplicate waiting

- [ ] Write focused failing tests for immediate dispatch on confirmed provider
  end-of-turn, with no configured settling delay or duplicate response.
- [ ] Test final transcript segments during continuing speech, eager/resume
  sequences, missing or late final text, duplicate endpoints and stale events.
- [ ] Remove the extra wait from the confirmed provider endpoint path. Preserve
  necessary text assembly and make the evidence/selected authority inspectable.
- [ ] Implement or retain the explicit local fallback: silence waiting, renewed
  speech cancellation, bounded pending state and cleanup. Prove that optional
  Silero onset does not introduce waiting into the provider endpoint path.
- [ ] Verify one compiled call through each endpoint mode, with repeated turns,
  old snapshot compatibility, source replacement, hold, transfer and teardown.

## Checkpoint C — Contextual multilingual barge-in

- [ ] Write failing playback tests for the acknowledgment and interruption cases
  below, including partial transcript revisions and overlapping caller audio.
- [ ] Separate caller activity/publication from interruption admission. Preserve
  continuous agent playback for acknowledgments; interrupt promptly once intent
  is established, without waiting for a completed sentence.
- [ ] Handle acknowledgment-to-correction transitions and unfinished thoughts
  without losing words, answering prematurely or creating duplicate turns.
- [ ] Exercise room-owned and provider-owned interruption profiles. Explicitly
  document unsupported profiles rather than masking automatic upstream cutoffs.
- [ ] Verify exact cancellation and spoken-history settlement for real
  interruptions, and unchanged output continuity for ignored acknowledgments.

## Checkpoint D — Latency and acceptance

- [ ] Measure last caller speech, endpoint decision, model dispatch/first text,
  first generated audio and first output delivery with correlated identities and
  compatible clocks. Record missing boundaries as unavailable.
- [ ] Measure actual caller-side playback in a controlled recorded test. Server
  audio egress and provider transcript-final timestamps cannot by themselves
  prove the full caller-perceived delay. Reuse the existing metrics contracts.
- [ ] Run the declared ordinary-turn corpus against the **1,000 ms** target;
  report every sample, sample count, median, p95, maximum and all misses. Separate
  interruptions, acknowledgments, failures and tool-dependent responses without
  silently excluding slow ordinary replies. A mean below one second is not a
  passing maximum; unresolved misses keep performance acceptance open.
- [ ] Measure acknowledgment false interruptions, missed/delayed real
  interruptions and premature answers per language. Set explicit pass thresholds
  during research before tuning against the acceptance corpus.
- [ ] Run controlled and live speech/listening acceptance, including telephony,
  for both endpoint modes and the scenarios below. Record provider/model,
  configuration and evidence; synthetic event timing alone is insufficient.
- [ ] Pass focused regressions, required root checks and Lean speech-state
  verification; update runtime documentation, milestone evidence and the index.

## Acceptance scenarios

| Caller behavior and context | Required result |
| --- | --- |
| "oui... oui" while the agent explains something | Agent audio continues; acknowledgment does not start a competing response. |
| Kannada acknowledgment, including the supplied "oudhu" example | Same behavior, verified with native-language audio and transcription variants. |
| "yes...yes..." or "hmm" while listening | Agent audio continues through the acknowledgment. |
| "Yes" answering the agent's completed question | Accept a complete answer; do not discard it because of its wording. |
| "Yes, yes, but change the appointment" during agent speech | Recognize the developing interruption, stop output and preserve the full caller input. |
| "Stop" or "Wait, that's wrong" during agent speech | Interrupt promptly, even though the utterance is short. |
| "I'd like to change my..." followed by a pause and continuation | Keep the thought pending; do not rush an answer to meet the latency target. |
| "Tomorrow" answering a scheduling question | Allow contextual turn completion without requiring a grammatical full sentence. |
| Long speech split into committed transcription segments | Preserve one continuing caller turn until valid endpoint evidence. |
| Local-detector silence followed by renewed speech before its deadline | Cancel the pending endpoint; keep listening without a duplicate response. |
| Noise, echo, repeated keepalives or a retired source's late event | No spurious interruption or response; preserve existing source/permission checks. |

Include accents, code-switching, different pause lengths and ambiguous emphasis
in the research corpus. The examples specify conversational intent, not words
that must always be ignored regardless of context.

## Design review — separate from implementation

Local specification/dependency review completed on 2026-11-14. This plan follows
the implemented speech/session/onset foundations and precedes delivery. It does
not require unfinished debug UI or guardrail milestones. Review identified the
old unconditional-onset interruption contract as an intentional behavior change,
and retained explicit gates for provider endpoint evidence, upstream cancellation
control, multilingual ambiguity, Silero fallback and actual playback measurement.

No provider research, implementation, live acceptance or one-second performance
result is claimed by this review. All task boxes and the index entry remain open.
