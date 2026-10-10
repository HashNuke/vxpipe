# STS telephony source cutover

Scope: the telephony counterpart of the committed WebRTC room source-cutover
slice. Twilio/Telnyx raw WebSock media must carry a source epoch fixed before
asynchronous `SocketDispatch`, stale epochs must drop at the room/Gateway
boundary without killing the socket, and marks/readiness/lifecycle must keep
flowing during a hold. This is the milestone task at
`labnotes/milestones/agent-speech-to-speech.md` ("Red-test Twilio and Telnyx raw
media queued at their WebSock callbacks before cutover ..."). Telephony room
coordination (close/retire/bind/arm/reopen) is the dependent task, not this
checkpoint.

## Discovery (what already exists)

- The enabler `efb63f66` stamps decoded Twilio/Telnyx media with a monotonic
  `received_at` and a private socket-lifetime `source_epoch` (`make_ref/0` in
  `init/1`) in `stamp_media/2`, before `SocketDispatch.submit/3`. `Leg`
  preserves the packet; `MediaSession.audio_frame/2` carries both into the
  `AudioFrame` and only falls back to handler time when `received_at` is nil.
- The socket epoch never rotates or is revoked. `MediaSession` drops media only
  under the transfer `handoff_gate` (`held?: true`); it has no source-epoch gate.
- WebRTC is the reference: `Connection` attaches with `source_control: true`
  (`webrtc/connection.ex:134`) and answers `:vxpipe_sts_source_hold` /
  `:vxpipe_sts_source_arm` through `Connection.SourceCutover`, which returns a
  receipt carrying `{attachment, token, receiver, old_epoch, held_epoch}` and
  uses two receiver-owned barriers.
- Telephony attaches with `source_control?: false`
  (`telephony/media_session_setup.ex:42` calls
  `engine.attach_connection(command, output)`), so `RoomAuthority.STSSourceCutover`
  never selects it as a source connection.
- The design contract is [STS activity provenance](20260923-0243-sts-activity-provenance.md)
  lines 82-105 and 229-242: assign the epoch in the WebSock callback before
  async dispatch, carry it unchanged to `MediaSession`, drop stale media with a
  successful dispatch ack, keep marks/readiness/lifecycle alive, and do not
  treat a socket-only ack as a Leg drain or form a Leg/MediaSession call cycle.

## Design/dependency review (before tests/runtime)

Ownership: the Call Engine room owns authorization and the cutover sequence; the
Gateway owns the socket epoch, the Leg transport and the MediaSession drop point.
The room already drives a `source_control?` connection with correlated async
`hold`/`arm`; telephony must expose the same boundary rather than a second
protocol.

Contract: mirror the WebRTC receipt shape and bounded deadlines. The socket
rotates its epoch only in mailbox order (a control message handled after
previously queued raw frames), so old queued media keeps the old stamp. The
MediaSession holds the expected active source epoch, independent of the transfer
`handoff_gate`; a media event whose epoch is not current is acknowledged `:ok`
and dropped. Non-media events are never epoch-gated.

Dependency order:
1. Socket source-epoch hold/arm protocol for Twilio and Telnyx, with mailbox
   ordering; marks/readiness/lifecycle responsive; socket not killed.
2. MediaSession source gate: stale-epoch media acknowledged and dropped;
   fresh-epoch media delivered; independent from `handoff_gate`.
3. Leg-backlog proof: media dispatched before a hold but handled after arm
   carries the old epoch and is dropped; a genuinely fresh frame is delivered.
4. Room wiring: telephony main attachment as `source_control: true`, socket/
   MediaSession hold/arm, and compiled telephony room hold/reopen. Depends on
   1-3 and on the existing room controller; tracked as the following milestone
   task, not this checkpoint.

Explicit limits: fences project-observable queues only. No remote capture,
ICE/DTLS buffering or TCP receipt-time guarantee is claimed. No synchronous
Leg-to-MediaSession cycle. STT release must not clear a transfer hold.

Rejected alternatives (already recorded in the design doc): stamping raw media
only when the callback eventually handles it; relaying through a process that
reads a mutable current epoch; treating a socket-only ack as a Leg drain;
clearing only the ingress queue; sending `:ended` on hold.

## Task breakdown

- [ ] T1 Twilio/Telnyx socket epoch hold/arm with mailbox ordering.
- [ ] T2 MediaSession source-epoch gate and stale drop.
- [ ] T3 Leg-backlog stale-media proof.
- [ ] T4 (dependent) room/telephony `source_control` wiring and compiled room.

## Progress

- [x] T1 Twilio/Telnyx socket epoch hold/arm with mailbox ordering.
  `Vxpipe.Gateway.Telephony.SourceEpoch` mints the held epoch on hold and adopts
  the room-chosen active epoch on arm; both sockets answer
  `:vxpipe_sts_source_hold` / `:vxpipe_sts_source_arm` replies through
  `SourceEpoch.reply/3`. Media handled before the hold keeps the old stamp;
  media after the hold gets the held stamp; after arm the active stamp. Marks
  stay live during the hold and the socket is not stopped.
- [x] T2 MediaSession source-epoch gate and stale drop.
  `Vxpipe.Gateway.Telephony.SourceGate` is `nil` before cutover,
  `{:held, epoch}` during a hold and `{:active, epoch}` after arm.
  `MediaSession` now admits a media event only when
  `SourceGate.admitted?(state.source_gate, media.source_epoch)` is true;
  otherwise it acks `:ok` without touching the engine. The gate is independent
  of the transfer `handoff_gate`.
- [x] T3 Leg-backlog proof. With the Leg suspended, a media frame is stamped and
  queued before the hold; after hold and arm, resuming the Leg delivers the
  frame with its pre-hold epoch while a later frame carries the active epoch.
  The stale frame is therefore dropped by the T2 gate, and the socket keeps
  running.
- [ ] T4 (dependent) room/telephony `source_control` wiring and compiled room.

## Evidence

- `test/vxpipe/providers/twilio/telephony_media_socket_test.exs` (12 tests) and
  `test/vxpipe/providers/telnyx/telephony_media_socket_test.exs` (9 tests)
  include the hold/arm rotation and stalled-Leg cases.
- `test/vxpipe/gateway/telephony/source_gate_test.exs` (3 tests) and the
  direct-call drop case in
  `test/vxpipe/gateway/telephony/media_session_test.exs`.
- Broader focused group: `sts_input_test.exs`, `test/vxpipe/gateway/telephony`,
  both provider socket files — 134 tests, 0 failures, seed 0.
- `mix compile --warnings-as-errors` and `mix credo --strict` (1,107 files, no
  issues) pass.

## T4 design (room wiring, not yet implemented)

Room-facing boundary: the telephony `MediaSession` is the analogue of the
WebRTC `Connection`. `RoomAuthority.STSSourceCutover` already sends
`{:vxpipe_sts_source_hold, %{attachment, token, deadline_ms}}` and
`{:vxpipe_sts_source_arm, %{..., active_epoch, ...}}` to a connection whose
room map has `source_control?: true`, and expects a
`{attachment, token, receiver, old_epoch, held_epoch}` receipt / active-epoch
reply.

- `MediaSessionSetup.run/1` attaches the main telephony connection with
  `source_control?: true` (WebRTC already does this) so the room selects it.
- The MediaSession authorizes `caller == state.attachment.room_authority` and
  `scope.attachment == state.attachment.room_monitor`, then forwards the
  request to `state.socket_owner` with `reply_to: self()`. It replies to the
  room only after the socket ack, mapping the socket receipt's `socket` pid to
  the room `receiver` field and setting `source_gate` on hold/arm. A bounded
  timer fails the request closed and leaves the gate held.
- The socket's `old_epoch`/`held_epoch` and the room-chosen `active_epoch` are
  the same values `SourceEpoch` already handles, so no new epoch protocol is
  needed.
- Verification: a compiled telephony room with selected STS completes
  hold → retire STT → fresh origin → arm → reopen; a frame queued before the
  hold is dropped by the `SourceGate`, a fresh frame is delivered, and marks
  stay responsive. Telephony raw source cutover acceptance remains separate.

Implementation status: `MediaSession` now authorizes the room authority and
exact room monitor, forwards hold/arm to the socket owner, settles only on the
socket ack, and times out to `{:error, :source_unavailable}` with the gate left
held; `MediaSessionSetup` attaches telephony media with `source_control?: true`.
Focused direct-handler tests cover the authorized hold→arm sequence and an
unauthorized caller; the adjacent 190-test group passes seed 0. The compiled
telephony room hold/reopen test remains the next step.

## Limits

T1-T3 are enabling primitives. The MediaSession gate stays `nil` until T4 wires
the room's hold/arm through `MediaSessionSetup` (`source_control?: false` today)
and the MediaSession forwards to the socket owner. No end-to-end telephony room
cutover, remote-capture, ICE/DTLS or TCP receipt-time claim is made. The socket
hold is mailbox-ordered, so it fences project-observable queues only.
