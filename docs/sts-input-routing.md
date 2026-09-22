# STS microphone routing

Status: directional formats, bounded ingress and the embedded real-room PCM
round trip have focused implementation evidence. Native WebRTC/telephony input
conversion, delivery and phone-room readiness now pass focused tests; complete
multi-mode native calls and milestone acceptance remain unfinished. This preserves the existing
[STS milestone](milestones/agent-speech-to-speech.md) requirements.

## Evidence and decision

Initial inspection found that the real-room startup probe reached readiness and
verified source-disconnect cleanup without delivering microphone audio.
`ConnectionAttachment.media_ingress` refers only to human STT, and
`CallEngine.push_audio/2` rejects an
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

## Implemented room binding

`ConnectionAttachment.speech_to_speech_input` is a private identity-and-owner
lookup, independent of the human STT PID. It can be created before asynchronous
entry preparation finishes. Only the pinned caller's admitted human connection
can create the registered input. Startup installation revisits earlier attached
connections. The transport resolves `speech_to_speech_input_configuration/1`
during preparation and offers PCM using `push_speech_to_speech_audio/2` from its
owning process. Per-frame delivery performs no room or policy authority call.

After provider readiness, the room starts ingress beneath the agent tree and
registers ingress plus capability as one connection-bound policy group. The
candidate controller starts held. The readiness graph requires the selected
STS ingress as well as the provider allocation; a microphone track alone is
insufficient. Native adapters that omit STS preparation fail closed.

Release opens prepared input with a new epoch. The receiver independently checks
that epoch, exact ingress and source identity, policy revision, prepared PCM
track/format, sequence and age before consuming bytes. Hold closes ingress and
invalidates its epoch, including messages already in transit. Production room
allocations reject raw, unframed capability input. Source, ingress or capability
loss tears down the temporary allocation tree.

The embedded real-room test encodes HI, sends PCM through the attachment API,
decodes sink output as RECEIVED HI, and observes caller and agent transcripts
through the real room publisher/router. Agent text is withheld until playback
settlement. This also exposed and fixed the distinction between global policy
revision and source-specific transcript interval; transcript evidence carries
the latter to the room. Agent output retains its admission interval across
transcript revoke/regrant so settlement cannot relabel old speech as new.
Local queue and embedded PCM tests are not native
transport conversion or independent live STT/STS fanout proof.

## Native input adoption

Gateway's `Media.STSInput` prepares the selected input format using the exact
connection-bound allocation. WebRTC and telephony retain separate native
conversion state for STS and human STT. Initial readiness requires a source
track and the STS ingress resource with the current policy revision, even when
human STT and room input are not demanded. Unsupported conversions and missing
allocations fail preparation. STS transfer-candidate preparation is explicitly
unsupported pending the milestone's source-handoff contract.

Each microphone frame is offered to the independent STS, human-STT and room
inputs before aggregating their results. Full queues drop independently;
temporary STS policy denial drops a frame without terminating the transport.
The STS ingress owns credit, bounds and permission checks. WebRTC extends its
16-bit RTP sequence at this boundary and rejects late/duplicate packets before
updating native decoder history; telephony retains its own sequence semantics.

Focused tests exercise stereo WebRTC Opus48k, Telnyx Opus16k and Twilio PCMU8k
conversion to monoPCM16k, both transport callbacks, both directions of STT/STS
backpressure, policy deny/regrant and one supervised Telnyx room reaching ready
without human STT. These are local codec/socket checks, not live carrier or
rendered browser interoperability. Full native conversation acceptance remains
separate from the embedded PCM round trip.

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
is in `labnotes/20260922-1233-sts-microphone-routing.md`. Room binding and the
embedded PCM round trip are recorded in `labnotes/20260922-1309-sts-room-input.md`.
Native adoption evidence is in `labnotes/20260922-1344-sts-native-input.md`.
Integrated native conversations, all transcript modes and complete lifecycle
acceptance remain open.
