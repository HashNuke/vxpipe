# Gateway source cutover

Status: design investigation for the existing unchecked STS source-time fence;
no Gateway implementation or room hold acceptance is claimed.

## Reproduced problem

Astra xhigh suspended a callback-delegating test process, queued raw WebRTC
RTP or telephony media before STT ingress reopened, then resumed the callback.
Both paths built `AudioFrame.received_at` after the cutoff and dispatched old
payload. Supplying the original pre-cutoff timestamp instead made the committed
STT ingress return `{:error, :stale_frame}`. This is a source timestamp gap,
not a regression in commit `05b02718`'s ingress check. The milestone records
it under the existing cutover task.

## Current process path

- ExWebRTC `PeerConnection` emits `{:ex_webrtc, peer, {:rtp, ...}}` to the
  configured controlling process. `Vxpipe.Gateway.WebRTC.Connection` drops RTP
  when its handoff gate is held; otherwise `IncomingAudio.forward_connection`
  builds an `AudioFrame` with `System.monotonic_time(:millisecond)` when its
  handler runs. The WebRTC speech normalizer preserves `received_at`.
- Twilio/Telnyx WebSock owners decode raw frames and dispatch `Telephony.Event`
  asynchronously through `Gateway.Telephony.Leg` to `MediaSession`. The latter
  drops media while its handoff gate is held; otherwise it builds `AudioFrame`
  with handler-time `System.monotonic_time(:millisecond)`. Telephony speech
  normalization preserves that field.
- `Media.HandoffGate` currently holds output and sets a held flag on the
  Gateway callback. Its release handler opens STT ingress before clearing the
  flag. It does not by itself close/retire selected native STT or provide a
  source-issued generation across the upstream processes.

## Design constraints and next proof

An ingress-only timestamp or a clock read inside the eventual Gateway handler
cannot classify raw media already queued upstream. An acknowledged source
barrier must precede release, or the source must issue a generation before
asynchronous forwarding. WebRTC's callback mailbox and telephony's WebSock →
Leg → MediaSession chain need separate focused reds; process ordering must be
proved across every hop, not inferred from one GenServer call. A synchronous
MediaSession wait on a socket barrier may deadlock if prior socket events need
MediaSession to finish first; prefer an asynchronous continuation or a worker-
owned sequence if that concern is confirmed by a focused test. Keep room STT
close/retire/ready/rebind/open and external/hybrid controller wiring unchecked
until the source fence is proven.

## Reviewed candidate and correction

The handoff worker already calls each connection adapter's `hold/2` and
`release/3`; `Gateway.Media.ConnectionReadiness.binding/4` carries a transport
binding. WebRTC's binding includes the ExWebRTC peer PID, and telephony's
includes the WebSock owner PID. A source barrier may help establish order, but
the first hypothesis below was too weak by itself:

1. Keep the Gateway callback held and selected STT ingress closed.
2. Acknowledge the upstream source process after its already-enqueued raw
   media has been emitted or dropped. For WebRTC, the peer is a GenServer that
   emits RTP directly to its controlling connection process; a peer call may
   establish a sender-order barrier, subject to focused proof against its
   actual worker topology.
3. For telephony, the WebSock owner submits events asynchronously to `Leg`,
   which synchronously calls the MediaSession backend. A socket acknowledgement
   alone is too early; a subsequent Leg acknowledgement must wait until the
   older media dispatches have completed while MediaSession is held.
4. Only then bind/open the fresh STT origin and clear the Gateway held gate.

Scoped Astra xhigh design review reproduced raw-message bypasses in both
Gateway paths using in-memory tests delegated to real callbacks. For WebRTC,
queued raw RTP had a pre-cutover monotonic time while its eventual `AudioFrame`
was stamped afterward; telephony behaved the same. The reviewer proposed an
acknowledged source-admission epoch fixed before asynchronous forwarding. The
epoch must stay immutable in an old receiver or a WebSock event; a mutable
relay merely moves the race. WebRTC's `PeerConnection.controlling_process/2`
can change the notification destination without replacing the peer, but the
default synchronous timeout and non-media ordering need proof. Telephony must
carry the epoch through SocketDispatch and Leg; a socket ack alone cannot
drain Leg, and stale media should ack `:ok` rather than kill the socket. A
MediaSession-to-socket-to-Leg synchronous cycle must be avoided.

This is not yet an implemented or fully approved contract. The reviewer did
not test a live peer or phone socket, and no local barrier proves remote
capture, ICE/DTLS buffering or TCP receipt-time semantics. The milestone now
breaks the work into WebRTC, telephony and coordinated ordering/failure tests
under its existing source-time task. The next step is focused red tests at
each owning callback boundary; no hosted provider is involved.

## Telephony provenance enabler

Focused Twilio and Telnyx socket tests sent decoded media through the actual
asynchronous Leg dispatch, with Twilio's Leg suspended until both start and
media requests were queued. Both initially failed on missing `received_at` in
the media packet. A Gateway MediaSession/STS-input test then failed because
the delivered frame's `received_at` was assigned during MediaSession handling,
not retained from its packet (observed values differed by 12 ms in the first
red run). These are local callback/queue reproductions, not live WebSocket
arrival proofs.

`MediaPacket` now carries optional paired, validated monotonic `received_at`
and private `source_epoch` evidence. Both WebSock callbacks stamp the pair
before SocketDispatch; MediaSession preserves it in `AudioFrame`, including
through telephony STS conversion. Direct project-owned events without the
socket provenance retain the previous handler-time compatibility path.
The focused Twilio/Telnyx/STS-input group passes 28/0 (seed 0). No source
hold/arm API, raw-mailbox fence, stale-epoch rejection or room coordination
exists yet; the milestone parent task stays unchecked.

Astra xhigh read-only review reran the 28-test focused group and 13 in-memory
probes (all green). The probes covered wire-field spoofing, paired packet/event
validation, negative/zero monotonic times, default timebase, distinct socket
epochs, stalled Leg delivery for both providers, wrong-owner rejection,
PCMU/Opus conversion and legacy unstamped events. No actionable runtime
defect was reproduced. Review found two inaccurate documentation phrases
about the current telephony stamp point and which committed provider test
suspends Leg; those were corrected. This review does not satisfy the open
hold/reopen or native-socket acceptance tasks.
