# Caller speech recovery on telephone calls

## Decision

For an established inbound Telnyx call with a human caller using ElevenLabs Scribe, give the room one bounded opportunity to restore recognition while the phone audio path works. Give the surviving carrier leg ownership of the final announcement, transfer and hangup when room audio fails. Start delivery with the carrier exit so every later retry can fall back to a working exit. See the [implementation and handset acceptance plan](../../labnotes/milestones/caller-speech-recovery.md).

On the November 24 QA trial the room stopped agent playback on caller onset. The last turn produced no final transcript. Roughly 10.5 seconds later STT failed, the media session exited, and the database still listed the carrier leg as active. The originating STT fault is unknown. [Redacted incident timeline](../../labnotes/20261124-0807-caller-recovery-milestone.md#failed-qa-trial-november-24-utc)

## Ownership and implications

The room can distinguish continued speech, provider progress, recognition readiness and media ownership. Only the carrier leg can issue an independent announcement after room media exits. Preserve the failure classification across that boundary. Use a pre-provisioned recording, stable carrier command identities, bounded waiting and the existing carrier termination evidence. An accepted command alone cannot establish that anyone heard the message or that the call ended.

The original carrier owner accepts recovery before AI room teardown. An explicit whole-call hangup takes priority. Owner loss without carrier evidence leaves an unresolved outcome; storage recovery alone cannot recreate runtime ownership. During a database outage the surviving owner retains stable command identities and can announce and end its known caller leg.

A participant-scoped operational Silero offset may arm a stall timer. Scribe remains the authority for completed text. Passive benchmarking stays observational. Scope the first timed profile to operational Silero, with confirmed STT failures eligible for handling even without a local offset. Tenant transfer routing requires an explicitly provisioned destination. An absent destination selects announcement and hangup. Recovery prompts are system audio with their own delivery evidence.

## Alternatives considered

- Retrying inside the failing Scribe adapter cannot explain silence after room media exits or settle the carrier leg.
- Immediate hangup bounds carrier time but gives callers no explanation. Keep it as the last resort when even carrier playback fails.
- An onset-based timeout would interrupt long questions. Scoring short backchannels solves a different problem and remains in the [voice milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md).
- Replaying audio into a fresh session risks duplicate answers and transferring private or retired audio. Request a repeat once fresh recognition is ready.

Verification so far consists of the incident timeline, existing source boundaries and specification review. Implementation, carrier interoperability and handset audibility are acceptance gates below the linked milestone.
