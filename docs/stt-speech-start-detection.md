# STT speech-start detection

Status: implemented in the working tree, 2026-10-11; final acceptance is tracked in the
[implementation milestone](../labnotes/milestones/transcript-start-and-optional-vad.md).

## Decision

Human STT turns start when the first nonempty transcript arrives. Users can
turn on local Silero VAD for an earlier interruption signal with any supported
STT model. Local VAD is off by default; provider-side VAD can still be enabled.

Caller STT selection:

```json
{
  "speech_to_text": {
    "provider": "elevenlabs",
    "model": "scribe_v2_realtime",
    "vad": true,
    "options": {"language_code": "en"}
  }
}
```

`vad` is a Vxpipe setting beside `provider`, not an upstream model option.
Omission and `false` select transcript-based start. `true` adds local VAD;
transcripts remain a fallback if VAD misses the utterance. An inherited selection
inherits its setting; an explicit selection replaces the whole selection as it
does today. This API-only setting has no Console toggle. It applies to human `speech_to_text`, not agent
`output_speech_to_text`, TTS, LLM or provider-controlled STS.

| Setting | Human turn starts when | Human turn ends when |
| --- | --- | --- |
| Omitted or `false` | First nonempty interim transcript, or final text if no interim arrives | The recognizer supplies its existing conversational endpoint |
| `true` | Local VAD confirms onset, with transcript fallback | The same recognizer endpoint; local silence does not finalize recognition |

Scribe uses `commit_strategy: vad` in both modes, allowing automatic
transcript commits. Raw manual protocol helpers and historical pinned plans retain their existing behavior. The portable Scribe selection currently exposes language, not a
commit-strategy override, so new human-STT selections use this conversational default.

## Provider boundaries

| Recognizer | Endpoint retained by the common wrapper | Eager/resume |
| --- | --- | --- |
| Deepgram Flux | Provider semantic end with cumulative text | Preserved |
| Google live transcription | Provider semantic end; delayed finals retain native correlation | Not advertised |
| Cartesia Ink | Provider semantic end with cumulative text | Preserved |
| Local Morse | Existing provider gap | Not advertised |
| ElevenLabs Scribe | Explicit inferred transcript gap across automatic segments | Not advertised |

All receive the same common onset choice. Existing raw provider adapters remain
available for agent-output transcription and historical compiled input plans.

## Turn ownership

One shared, allocation-owned coordinator combines recognizer and optional VAD
evidence before publishing semantic events. It emits one start before text for
each conversational turn. Provider onset hints may establish correlation but do
not interrupt by themselves in default mode. Empty and repeated partials do not
start turns. Later transcript revisions update the existing turn.

Local VAD observes the same permitted PCM without gating recognition or dropping
quiet speech. Its early start and the later provider turn map to one canonical
turn. A provider segment is not automatically a new acoustic turn: cumulative
text, eager endpoints, resumes and segment boundaries must retain the provider's
conversation semantics. Scribe has the inferred endpoint described below. Nonempty final-only results emit start, text
and end in order. Empty recognition results never create model input.

With local VAD off, startup does not load Silero or create per-allocation VAD
workers. With it on, the allocation owns the detector, bounded queues and
recurrent state. Its branch receives mono 16 kHz PCM through the owning media
conversion path even when the recognizer uses another rate or encoded audio.
Retiring or replacing a permission interval retires both
recognition and detection; late events cannot acquire a newer interval's identity.

WebRTC source hold recreates STT Opus decoding and mono re-encoding resources before
rearming the source. Format and ingress identity are retained. If reset fails, the
source remains held without an armable receipt. The detector's PCM resampler uses
absolute sample timestamps and carries no history across frames or allocations.

## Implications and evidence

The [Scribe measurement](../labnotes/20261011-0333-scribe-partial-latency.md) found
a median first-partial delay of 1,259 ms from estimated acoustic onset, and
1,098 ms after live Silero confirmation, across twelve clean synthetic utterances.
The latter ranged from 810 to 1,369 ms. These figures exclude room dispatch and
playback cancellation and do not establish performance for other models or noise.
The user accepted this tradeoff as the default; local VAD offers faster
onset when wanted.

Scribe automatic commits are segments, including forced commits during long speech.
The hosted probe observed one during continuous input at 36 seconds; wire events
contained only `message_type` and `text`, without a commit-reason discriminator.
Treating every commit as `provider_gap` would end long turns early.

The continuous adapter therefore reports **`inferred_gap`**: after a committed
segment, 1.5 seconds without changed nonempty text, and with no outstanding
draft, settles the committed cumulative snapshot. New draft recognition cancels
settlement until it commits or fails its deadline. A draft after an earlier commit
requests one explicit commit after 1.5 seconds without revisions, retaining VAD
strategy. Its response has a five-second deadline; empty segments cannot promote
uncommitted words or clear that deadline. Duplicate and empty keepalives
do not create boundaries. The [ElevenLabs API reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
explicitly permits keepalives to repeat an uncommitted partial. This is a heuristic,
and can split an utterance if recognition stops revising while someone continues
speaking. Local VAD changes onset only and does not strengthen that endpoint claim.
A missing commit fails after 60 seconds of draft recognition; an open canonical
turn without further text or an endpoint fails after 60 seconds of inactivity.

Existing serialized selections missing `vad` retain native onset and manual Scribe
behavior. New selections default to false. Omitted/false retain historical
selection hashes; true changes the hash. Existing publications are not rewritten.

## Alternatives considered

- Always-on local VAD gives early onset but conflicts with the requested default
  and makes every recognition allocation depend on acoustic inference.
- An ElevenLabs-specific toggle duplicates turn handling and cannot serve other
  STT models consistently.
- Provider onset events as the default are fast where available, but do not
  implement the requested transcript-based start consistently across providers.
- Letting VAD silence end every turn would replace existing provider endpointing
  and change semantic turn-taking beyond this speech-start setting.

## Verification

Focused tests cover parsing, inheritance, canonical event ordering, empty finals,
VAD fallback, stale recognition/inference, preparation and teardown, PCM/Opus
normalization and historical compiled plans. Save/publish tests preserve explicit
true/false, and rendered source editing preserves the field through provider
changes and draft save without adding a control.

Hosted checks passed distinct and repeated short turns, quiet input after
settlement, 45-second input and low-level synthetic background noise in both onset
modes. WebRTC/RTVI checks verify that a blank native onset leaves agent output
running, while the first nonempty transcript interrupts it and leads to the next
reply. The speech-start milestone is complete under the first-partial acceptance
criterion. A [Scribe recognition issue](../labnotes/issues/scribe-appended-short-answer.md)
remains in a repeated-speech fixture; human listening has not been performed.
These limits do not change the verified start-event ordering. The latency
measurement remains opt-in. Final evidence and follow-ups are recorded in the
milestone and [implementation labnotes](../labnotes/20261011-0510-implement-transcript-start.md).
