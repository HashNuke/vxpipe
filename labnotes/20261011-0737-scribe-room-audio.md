# Scribe room audio

## Question

The configured published-room corpus omits its appended brief answer in hosted
Scribe partials and commits. Before attributing this to recognition, verify the
entire admitted fixture reaches the socket adapter unchanged, in order and on one
owned connection.

## Measurement

The opt-in ScribeEvidenceSocket emits only accepted outbound chunk byte counts,
SHA-256 digests and its socket identity through test telemetry. The configured
room test compares that trace against the original fixture chunk boundaries before
its existing word-fidelity assertions. It never logs PCM, provider credentials or
raw transcripts. The production adapter is unchanged. The trace is enabled only
with VXPIPE_TRACE_SCRIBE=1 in the explicitly tagged live lane through bin/livetests.
The credential file is loaded only by the runner's child; it is never inspected.

An exact trace proves delivery to the socket send API, not a server-side audio
acknowledgement. Existing protocol encoding tests and live connection lifecycle
provide the adjacent evidence. The existing missing-word assertion stays intact.

## Outcome

The selected hosted configured-room test verifies all 774,400 fixture bytes in
order on one socket (seed 906572). It still fails its unchanged appended-answer
assertion. No provider partial or committed wire message contains that answer.
This rules out omission/reordering/change before the socket send API in this run,
while retaining the server-acknowledgement limit above. The current repeat-heavy
synthetic corpus exposes recognition fidelity that the common onset coordinator
cannot repair. Do not manufacture the missing text or loosen its acceptance test.
No further paid retry is justified without a changed diagnostic question, provider
state, or explicit acceptance decision.

## Intra-utterance pause diagnostic

On resumption, tested whether directly splicing the brief answer onto the repeated
phrase caused the omission. Added 300 ms of quiet PCM before the answer, keeping
the existing single-turn and both-word assertions intact. The hosted case still
fails the answer assertion (seed 901442, 30.7 seconds). Its trace verifies all
784,000 bytes in order on one socket; neither partials nor commits contain the
answer. This does not support the simple splice-boundary explanation. Restored
the original fixture construction rather than retain an ineffective test change.
No production behavior changed. Telephony is excluded from this milestone.
