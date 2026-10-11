# ElevenLabs realtime STT session

Status: implemented; accepted for transcript-based speech start. Recognition and
human listening follow-ups are recorded below.

New human-STT selections use Scribe v2 realtime with automatic VAD commits.
Human speech starts with the first nonempty transcript by default. Add `vad: true`
to use local Silero onset with transcript fallback; this API setting has no Console
control and never becomes an upstream Scribe option.

```json
{
  "speech_to_text": {
    "provider": "elevenlabs",
    "model": "scribe_v2_realtime",
    "credential_name": "voice",
    "vad": false,
    "options": {"language_code": "en"}
  }
}
```

Language is optional. Recognition uses mono S16LE PCM at 16 kHz.
The encrypted tenant credential or inherited platform service is resolved privately
at startup. Publications and compiled plans contain no key. The same ElevenLabs
service supports STT and TTS; it advertises no STS capability.

## Turns and endpoints

One continuous recognition connection belongs to each permission allocation.
Partials revise the current segment; committed segments accumulate into the current
turn. Scribe can force a commit during long speech and supplies no commit-reason
field, so a commit alone does not mean the caller finished speaking.

The adapter declares `inferred_gap`. After a commit, 1.5 seconds without a changed
nonempty transcript, with no outstanding draft, settles the committed cumulative
snapshot. A changed partial cancels the candidate. If a draft remains after an
earlier commit, 1.5 seconds without revisions requests one explicit commit while
keeping VAD strategy. Settlement requires nonempty committed text; an empty
response preserves the draft and deadline. The request fails after five seconds
without a committed response. Duplicate or empty keepalives do not create boundaries.
This inference can split speech when recognition stops revising despite continued
speaking. It is not provider-semantic or acoustic endpoint evidence. Local Silero
changes onset only; its silence does not commit recognition or end the turn.

No transcript means no default speech-start event. Final-only recognition produces
start, text and end in order. Empty recognition never supplies model input.
Unsettled draft recognition has a 60-second commit deadline. The shared coordinator
also bounds an open turn's inactivity while awaiting text or an endpoint.

See [speech-start detection](stt-speech-start-detection.md) for the common contract
and the measured interruption tradeoff.

## Ownership and failure

The allocation owns the socket, transcript assembly, turn references and optional
Silero recurrent state. Startup requires the provider acknowledgement and, with
local VAD enabled, detector preparation. With VAD off no detector is prepared.
Closing, replacing or denying the permission interval retires both recognition and
activity; stale results cannot publish into its replacement.

Input remains credited and bounded. The recognizer receives accepted audio once;
the optional detector observes normalized PCM without gating recognition. Accepted
input usage remains owned by the outer capability. Reported turn duration measures
submitted PCM, including silence, rather than claiming provider billing evidence.
Inspection redacts credentials, PCM and transcripts. Socket keepalives contain no
PCM and do not advance usage or create turn events.

## Compatibility and verification

Historical compiled selections missing the common `vad` field retain the previous
manual adapter: local acoustic boundaries, fresh connections per acoustic turn and
serialized twenty-second recognition segments. Raw protocol helpers also retain
manual defaults. Agent-output STT remains on its existing raw-provider path.
Immutable publications are not rewritten.

Local tests cover continuous input, segment assembly, single-flight draft flushing,
empty responses, timeout failure, ordinary close and allocation retirement. Hosted
checks passed distinct and repeated short turns, quiet input after settlement,
and 45-second input in both onset modes. The speech-start milestone is accepted.
The [appended-answer recognition issue](../labnotes/issues/scribe-appended-short-answer.md)
remains a follow-up with its live assertion intact; human listening is unperformed.
Evidence is tracked in the [milestone](../labnotes/milestones/transcript-start-and-optional-vad.md)
and [implementation labnotes](../labnotes/20261011-0510-implement-transcript-start.md).
Historical manual-mode acceptance is recorded in the
[original session labnotes](../labnotes/20261001-0230-scribe-local-session.md) and
[configured-room checkpoint](../labnotes/20261001-0505-scribe-configured-room.md).
