# STS microphone routing

Status: directional formats and the independent ingress primitive have focused
implementation evidence. Room/transport wiring and end-to-end acceptance remain
unfinished. This preserves the existing
[STS milestone](milestones/agent-speech-to-speech.md) requirements.

## Evidence and decision

The real-room startup probe now reaches readiness and verifies source-disconnect
cleanup. It does not deliver microphone audio. `ConnectionAttachment.media_ingress`
currently refers only to human STT, and `CallEngine.push_audio/2` rejects an
attachment without it. WebRTC and telephony both derive their speech conversion
from that one handle. `Ingress.set_sts_target/2` has no production caller, and
its uncredited send runs only when the STT queue dispatches a frame.

Use an explicit, separately bounded STS input handle bound to the authorized
source connection and the agent allocation. Its execution belongs beneath the
agent's room-owned tree; it must stop with that tree or source connection.
Keep human-STT and STS admission independent, including conversion state,
queue/byte/age limits, one outstanding delivery credit, and drop accounting.
Only the caller's source frame is eligible; no mixed room output is input.
An overload or stalled STT consumer must not delay or grow the STS queue, and
the reverse must also hold.

The ingress validates tenant, room incarnation, source participant, exact
connection, track, PCM format, sequence/age and current policy interval before
delivery. Policy revocation and hold fence queued input before acknowledgement.
Prepared/held connections cannot admit live audio. No per-frame synchronous
call into RoomAuthority or the policy authority is added.

Only the authorized caller connection may bind the input handle; attaching a
monitor or unrelated participant must not create an STS source. Keep candidate
input/output closed until the policy enforcer and room readiness barrier have
accepted the exact allocation, including when policy changes during startup.

## Format and readiness contracts

STS descriptors now require separate validated `input_format` and output
`format`: Google declares 16 kHz input and 24 kHz output; Morse declares its
selected rate in both directions. Missing/invalid input PCM fails validation.
Existing STT/TTS contracts keep their meaning and `input_format: nil`.
Gateway must not infer input format from output or special-case provider names.

Gateway should reuse its existing Opus/PCMU conversion functions with separate
per-consumer state and explicit unsupported-format errors. Both transport
readiness implementations must prepare and verify STS input when selected,
even when human STT is absent. Include the exact ingress/allocation binding in
the room readiness graph. Cover connections attached before asynchronous entry
preparation finishes, as well as the already-prepared path.

## Implemented admission primitive

`Media.STSIngress` starts closed and requires an ordered policy snapshot plus
an exact prepared track before opening. It validates full source identity,
membership, source-to-agent audio permission, mono PCM format, frame age and
monotonic sequence. Its independent queue counts both waiting and outstanding
frames against the byte/frame bounds. One capability delivery is outstanding
at a time; only the matching capability/reference acknowledgement releases it.
Queued frames are age-checked again at delivery.

Defaults are 25 frames, 32,000 bytes, a 250 ms maximum age and a 1,000 ms
delivery acknowledgement deadline. Limits must be positive integers, with
private acknowledgement timeout overrides capped at 5,000 ms. A stalled
delivery retires the ingress. Policy installation conservatively discards all
queued frames, including on unrelated revisions; hold discards queued frames
and keeps input closed until explicit release. Neither grants an additional
credit while the earlier delivery remains outstanding. Source or capability
loss retires the temporary ingress. Process status redacts buffered audio.

This primitive does not yet have a production caller. The room integration
must supervise it beneath the allocation, register both input and capability
as one policy-enforcement group, and prepare transport conversion before
opening admission. The capability must revalidate exact ingress/source,
current policy revision and held/adoption state before consuming a delivered
frame; a sender-side check cannot retract a message already sent. The room's
readiness inventory must cover both the ingress and provider allocation.
Do not present these local queue tests as independent live STT/STS fanout proof.

## Rejected shortcuts

- Wiring the existing STT-dispatch hook: couples STS progress to STT demand and
  credits, passes possibly wrong-format bytes, and can grow the STS mailbox.
- Feeding the mixer output: loses the single-source identity boundary and risks
  echoing agent speech back into the conversational model.
- Requiring human STT: removes the explicitly required provider-transcript mode.
- Treating a running provider as a runnable call: omits input preparation,
  publication and transport/lifecycle acceptance.

## Verification sequence

Write failing format, bounded admission and independent-consumer tests first.
Then drive a compiled real room with encoded Morse caller audio and decoded
Morse reply audio, asserting caller turn events and exactly one agent transcript
after playback settlement through EventPublisher/TranscriptRouter. Repeat with
human STT and with agent-output STT. Exercise denial/revocation, hold, duplicate
sources, early attachment, cleanup and stale-frame rejection. Verify WebRTC and
telephony conversion/readiness separately before the three-mode ten-call load.
No new hosted or billable calls are authorized by this decision.

Inspection evidence is recorded in
`labnotes/20260922-1209-sts-room-integration.md`. The primitive/format evidence
is in `labnotes/20260922-1233-sts-microphone-routing.md`; integrated input-routing
acceptance checks have not passed yet.
